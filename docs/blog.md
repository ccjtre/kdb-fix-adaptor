# Kdb+ and FIX messaging: Working with repeating groups


The Financial Information Exchange (FIX) protocol is the de-facto standard for electronic transaction communication in financial markets. It is widely used by both buy-side and sell-side participants across a range of asset classes including equities, forex, interest rate securities and derivatives. 

Interfacing kdb+ with the FIX protocol has been previously explored in the [whitepaper by Damien Barker](https://code.kx.com/q/wp/fix-messaging/), which demonstrated how a table of order states could be efficiently constructed from a FIX message stream sent by an OMS. Further afield, [AquaQ released a library](https://github.com/AquaQAnalytics/kdb-fix-adaptor) in 2015 (currently in alpha state) which allows kdb+ to send and receive simple messages on a FIX session via the QuickFIX engine, a widely used open-source implementation of the protocol. 

This article focuses on how more complex FIX messages, namely FIX messages with repeating groups, can be sent and received from kdb+ using the QuickFIX engine. All code can be found in the [ccjtre/kdb-fix-adapter repo](https://github.com/ccjtre/kdb-fix-adaptor) on github, which extends the original AquaQ library. All tests were run using kdb+ version 4.0 2021.04.26.

## The FIX message format

FIX messages consist of ASCII SOH-delimited (Start of Heading) key-value pairs organized into a header, body and trailer, where the key is an integer tag representing an underlying field name as defined in the FIX specification. The header identifies the message type, length, destination, sequence number, origination point and time. Mandatory fields in the message header of particular interest in this blog include:

-	`BeginString` (8):  Denotes the FIX specification by which messages should be validated against, start of a new FIX message.
-	`MsgType` (35): Shorthand notation for the message type (EG: D for a `NewOrderSingle`, 8 for `ExecutionReport`).
-	`SenderCompID` (49): Unique identifier for counterparty sending the message
-	`TargetCompID` (56): Unique identifier for counterparty receiving the message

The body contains the business attributes of the message (for example, `OrderQty` (38) for a `NewOrderSingle`) whereas the trailer will generally just consist of the message `CheckSum` (10) which serves as the end-of-message delimiter along with its trailing SOH character.
Apart from the four fields mentioned above, QuickFIX will automatically add all required header and trailer fields to a message before sending, including `BodyLength` (9), `MsgSeqNum` (34) and SendingTime (52).

Examples of a typical `NewOrderSingle` (`MsgType`=D) and `ExecutionReport` (`MsgType`=8) are as follows:


```
8=FIX.4.49=13035=D34=249=CTRE52=20220317-18:00:31.73356=BROKER11=SHD2022.03.1721=238=876.040=154=255=TESTSYM60=20220317-18:00:31.73310=080
8=FIX.4.49=14235=834=249=BROKER52=20220317-18:00:31.74256=CTRE6=1.3814=87617=ORDER2022.03.1737=ORDER2022.03.1739=054=155=TESTSYM150=0151=123.410=002
```


Note that the FIX protocol does not enforce a specific tag order for the message body; this is not the case for members of repeating groups which will discussed below.
More information on the FIX message format, commonly used fields and message types can be found in [Damien Barker’s whitepaper](https://code.kx.com/q/wp/fix-messaging/).

FIX data dictionaries are widely available online. Unless otherwise stated, all examples in this article use the FIX 4.4 specification with reference to the data dictionary published by [ONIXS](https://www.onixs.biz/fix-dictionary/4.4/index.html).

## The QuickFIX engine

The [QuickFIX/C++ project](https://quickfixengine.org/c/) is an open-source implementation of the FIX protocol for C++, Python and Ruby covering the FIX 4.0 – 5.0 specifications. It enables the user to send and receive messages on a FIX session established with a counterparty will full data validation as defined by that session’s FIX specification and data dictionary. Multiple sessions can be maintained on a single process, and multiple sessions can even be maintained with a single counterparty.

### Session configuration

Sessions are configured via a settings INI file and are uniquely identified by the `BeginString`, `TargetCompID` and `SenderCompID` fields. The `SessionQualifier` field can be added to further differentiate between otherwise identical sessions. The INI file is comprised of a `DEFAULT` block and multiple optional `SESSION` blocks. `SESSION` blocks define a new session and will inherit settings from the `DEFAULT` block unless they are explicitly redefined in the session block.

The INI file used in the project for this blog is as follows:


```ini
[DEFAULT]
BeginString=FIX.4.4
ReconnectInterval=60
SocketAcceptPort=7091
SenderCompID=CTRE
TargetCompID=BROKER
TargetSubID=ADMIN
SocketNodelay=Y
PersistMessage=Y
FileStorePath=/var/tmp/quickfix/messages
FileLogPath=/var/tmp/quickfix/log

[SESSION]
ConnectionType=acceptor
StartTime=00:30:00
EndTime=23:30:00
ReconnectInterval=30
HeartBtInt=120
SocketAcceptPort=7091
SocketReuseAddress=Y
DataDictionary=src/config/spec/FIX44.xml
AppDataDictionary=src/config/spec/FIX44.xml
SenderCompID=BROKER
TargetCompID=CTRE
FileStorePath=/var/tmp/quickfix/messages
FileLogPath=/var/tmp/quickfix/log

[SESSION]
BeginString=FIX.4.4
ConnectionType=initiator
StartTime=00:30:00
EndTime=23:30:00
ReconnectInterval=15
HeartBtInt=120
SocketConnectPort=7091
SocketConnectHost=0.0.0.0
DataDictionary=src/config/spec/FIX44.xml
AppDataDictionary=src/config/spec/FIX44.xml
SenderCompID=CTRE
TargetCompID=BROKER
FileStorePath=/var/tmp/quickfix/messages
FileLogPath=/var/tmp/quickfix/log
```


Some fields of note:

-	`ConnectionType`: Denotes whether the `SenderCompID` of a given session acts as an initiator (initiates a session with a counterparty) or acceptor (accepts session initialisation from an initiator).
-	`SocketConnectHost` and `SocketConnectPort`: The host and port that an initiator connects to when establishing a FIX session with a counterparty. 
-	`SocketAcceptPort`: The socket port that an acceptor listens on for incoming messages.
-	`DataDictionary`/ `AppDataDictionary`: The XML data dictionary by which all messages on a session should be validated against. If no data dictionary is supplied then only basic message validation is applied. Note that a data dictionary must be supplied for sessions managing messages with repeating groups. `DataDictionary` is deprecated for sessions using the FIXT.1.1 specification onwards; For these you should specify `AppDataDictionary` and `TransportDataDictionary` which validate application level (eg: `NewOrderSingle`) and admin level (eg: `Logon`) messages respectively.

### The QuickFIX application interface

The virtual functions of the QuickFIX application interface define the callbacks invoked on various events in a FIX session, such as session creation, counterparty logon and logout, and application-level message receipt from a counterparty:


```cpp
namespace FIX
{
  class Application
  {
  public:
    virtual ~Application() {};
    virtual void onCreate( const SessionID& ) = 0;
    virtual void onLogon( const SessionID& ) = 0;
    virtual void onLogout( const SessionID& ) = 0;
    virtual void toAdmin( Message&, const SessionID& ) = 0;
    virtual void toApp( Message&, const SessionID& )
      throw( DoNotSend ) = 0;
    virtual void fromAdmin( const Message&, const SessionID& )
      throw( FieldNotFound, IncorrectDataFormat, IncorrectTagValue, RejectLogon ) = 0;
    virtual void fromApp( const Message&, const SessionID& )
      throw( FieldNotFound, IncorrectDataFormat, IncorrectTagValue, UnsupportedMessageType ) = 0;
  };
}
```


Of particular interest in this blog is the `fromApp` method, which receives application-level messages from a counterparty for a given `SessionID`. Our implementation creates a kdb+ dictionary representation of the `FIX::Message` object with the `ConvertToDictionary` function, and then writes the serialized dictionary to a socket which has the `ReceiveData` function bound to it via `sd1`. Finally, `ReceiveData` invokes the `.fix.onRecv` function in the kdb+ address space with the deserialized dictionary, which is analogous to the `.u.upd` function in a standard kdb+ tick setup.
  

```cpp
void FixEngineApplication::fromApp(const FIX::Message& message, const FIX::SessionID& sessionID) throw (FIX::FieldNotFound, FIX::IncorrectDataFormat, FIX::IncorrectTagValue, FIX::UnsupportedMessageType)
{
    WriteToSocket(ConvertToDictionary(message));
}
```


The code snippet below shows how we define an initiator or acceptor that listens on a socket. `Typename T` refers to either a `FIX::ThreadedSocketInitiator` or `FIX::ThreadedSocketAcceptor`. `settingsPath` is the path to the INI file discussed in the previous section, and `application` is our implementation of the QuickFIX application interface.


```cpp
template<typename T>
K CreateThreadedSocket(K x) {
    if (x->t != -11) {
        return krr((S) "type");
    }

    std::string settingsPath = "settings.ini";

    settingsPath = std::string(x->s);
    settingsPath.erase(std::remove(settingsPath.begin(), settingsPath.end(), ':'), settingsPath.end());

    auto settings = new FIX::SessionSettings(settingsPath);
    auto application = new FixEngineApplication;
    auto store = new FIX::FileStoreFactory(*settings);
    auto log = new FIX::FileLogFactory(*settings);
    
    dumb_socketpair(sockets, 0);
    sd1(sockets[1], RecieveData);

    T *socket = nullptr;
    socket = new T(*application, *store, *settings, *log);
    socket->start();

    return (K) 0;
}
```


The final piece we need for creating a fully functioning FIX counterparty in kdb+ is the `FIX::Session::sendToTarget` method. This overloaded method can accept a FIX::Message object and determine the intended session to send it to via to its `SenderCompID` and `TargetCompID` fields.

The next section discusses how initiators and acceptors can be initialized from kdb+.

## Creating initiators and acceptors in kdb+

The `.fix.init` function is used to initialize both initiators and acceptors in kdb+. It is dynamically loaded into the `fix.q` script from the shared library (see the [README](https://github.com/ccjtre/kdb-fix-adaptor) for build instructions).

`.fix.init` takes five arguments:

-	`senderCompID` (sym): The `SenderCompID` of your acceptor/initiator. Should agree with the INI configuration file (`configFile` argument).
-	`targetCompID` (sym): The intended `TargetCompID` for your acceptor/initiator. Should agree with the INI configuration file.
-	`counterPartyType` (sym): initiator or acceptor.
-	`configFile` (sym file handle): the INI configuration file for this FIX session.
-	`dataDictFile` (sym file handle): the data dictionary for this FIX session. Should agree with the INI configuration file. This is used to generate helper dictionaries in the q session; the data dictionary used by QuickFIX for validation will be sourced via the INI file.

The `.fix.init` function called as an acceptor will start a background thread that will receive and validate messages and finally forward them to the `.fix.onRecv` function if the message is well formed.


```q
/ q fix.q
q).fix.init[`BROKER;`CTRE;`acceptor;`:src/config/sessions/sample.ini;`:src/config/spec/FIX44.xml]
GetKMaps - Loading src/config/spec/FIX44.xml
CreateFIXMaps - Loading src/config/spec/FIX44.xml
Creating Acceptor
```

The `.fix.init` function called as an initiator will start a background thread that will open a socket to the target acceptor and allow you to send/receive messages.


```q
/ q fix.q
q).fix.init[`CTRE;`BROKER;`initiator;`:src/config/sessions/sample.ini;`:src/config/spec/FIX44.xml]
GetKMaps - Loading src/config/spec/FIX44.xml
CreateFIXMaps - Loading src/config/spec/FIX44.xml
Creating Initiator
```

Initializing either an acceptor or initiator via `.fix.init` also creates two useful dictionaries adhering to the `dataDictFile` argument: `.fix.tagNameNumMap`, which maps all numerical tags in the data dictionary to their underlying field name, and `.fix.msgNameTypeMap`, which maps message type names to their shorthand notation for use in messages:


```q
q).fix.tagNameNumMap
Account         | 1
AdvId           | 2
AdvRefID        | 3
AdvSide         | 4
AdvTransType    | 5
AvgPx           | 6
BeginSeqNo      | 7
BeginString     | 8
BodyLength      | 9
CheckSum        | 10
ClOrdID         | 11
Commission      | 12
CommType        | 13
CumQty          | 14
Currency        | 15
EndSeqNo        | 16
ExecID          | 17
ExecInst        | 18
ExecRefID       | 19
HandlInst       | 21
SecurityIDSource| 22
IOIID           | 23
..

q).fix.msgNameTypeMap
Heartbeat                | 0
TestRequest              | 1
ResendRequest            | 2
Reject                   | 3
SequenceReset            | 4
Logout                   | 5
IOI                      | 6
Advertisement            | 7
ExecutionReport          | 8
OrderCancelReject        | 9
Logon                    | A
News                     | B
Email                    | C
NewOrderSingle           | D
NewOrderList             | E
OrderCancelRequest       | F
OrderCancelReplaceRequest| G
OrderStatusRequest       | H
AllocationInstruction    | J
ListCancelRequest        | K
ListExecute              | L
ListStatusRequest        | M
..
q)

```

This is an extension of the original AquaQ library, which includes similar mappings albeit statically defined in the `fix.q` script (independent of the data dictionary/ FIX specification in use).

## Sending a simple FIX message from kdb+

The `.fix.send` function can be used to send a FIX message from an initiator to an acceptor. It accepts an integer-keyed dictionary with the integers representing the FIX message tags. Each value can either be of type string, sym or of a datatype analogous to the fields FIX type as specified in the data dictionary. The `BeginString`, `SenderCompID`, and `TargetCompID` field must be included in the input dictionary so that the library can determine the intended target session. The send is executed synchronously and will raise a signal upon error. Otherwise, you can assume that the message has been received successfully by the counterparty. 
The following example demonstrates sending a simple `NewOrderSingle` from an initiator to an acceptor, and the acceptor sending an `ExecutionReport` in response.


```q
/ initiator session
/ q fix.q

q).fix.init[`CTRE;`BROKER;`initiator;`:src/config/sessions/sample.ini;`:src/config/spec/FIX44.xml]
GetKMaps - Loading src/config/spec/FIX44.xml
CreateFIXMaps - Loading src/config/spec/FIX44.xml
Creating Initiator
q)8  | "FIX.4.4" / Logon received from acceptor
9  | 66f
35 | ,"A"
34 | 1i
49 | "BROKER"
52 | 2022.03.21D14:18:54.292000000
56 | "CTRE"
98 | 0i
108| 120i
10 | "037"

q).fix.sendNewOrderSingle
{[]
    message:()!();
    message[.fix.tagNameNumMap`BeginString]: "FIX.4.4";
    message[.fix.tagNameNumMap`SenderCompID]: string .fix.session.senderCompID;
    message[.fix.tagNameNumMap`TargetCompID]: string .fix.session.targetCompID;
    message[.fix.tagNameNumMap`MsgType]: string .fix.msgNameTypeMap`NewOrderSingle;
    message[.fix.tagNameNumMap`ClOrdID]: "SHD2015.04.04";
    message[.fix.tagNameNumMap`Symbol]: "TESTSYM";
    message[.fix.tagNameNumMap`Side]: enlist "2";
    message[.fix.tagNameNumMap`HandlInst]: enlist "2";
    message[.fix.tagNameNumMap`TransactTime]: 2016.03.04D14:21:36.567000000;
    message[.fix.tagNameNumMap`OrdType]: enlist "1";
    message[.fix.tagNameNumMap`OrderQty]: "876.0";
    .fix.send[message];
    }
q)
q).fix.sendNewOrderSingle[]
q)8  | "FIX.4.4" / ExecutionReport received from acceptor
9  | 142f
35 | ,"8"
34 | 3i
49 | "BROKER"
52 | 2022.03.21D14:21:34.708999936
56 | "CTRE"
6  | 1.38
14 | 876f
17 | "ORDER2015.04.04"
37 | "ORDER2015.04.04"
39 | "0"
54 | "1"
55 | "TESTSYM"
150| "0"
151| 123.4
10 | "003"

/ acceptor session
/ q fix.q

q).fix.init[`BROKER;`CTRE;`acceptor;`:src/config/sessions/sample.ini;`:src/config/spec/FIX44.xml]
GetKMaps - Loading src/config/spec/FIX44.xml
CreateFIXMaps - Loading src/config/spec/FIX44.xml
Creating Acceptor
q)8  | "FIX.4.4" / Logon from initiator
9  | 66f
35 | ,"A"
34 | 1i
49 | "CTRE"
52 | 2022.03.21D14:18:54.291000064
56 | "BROKER"
98 | 0i
108| 120i
10 | "036"

q)8 | "FIX.4.4" / NewOrderSingle received from initiator
9 | 130f
35| ,"D"
34| 5i
49| "CTRE"
52| 2022.03.21D14:24:28.363000064
56| "BROKER"
11| "SHD2015.04.04"
21| "2"
38| 876f
40| "1"
54| "2"
55| "TESTSYM"
60| 2016.03.04D14:21:36.567000000
10| "085"

q).fix.sendExecutionReport / callback invoked on receipt of NewOrderSingle
{[x]
    if[.fix.mode=`replay;:()];
    message:()!();
    message[.fix.tagNameNumMap`BeginString]: "FIX.4.4";
    message[.fix.tagNameNumMap`SenderCompID]: x[.fix.tagNameNumMap`TargetCompID];
    message[.fix.tagNameNumMap`TargetCompID]: x[.fix.tagNameNumMap`SenderCompID];
    message[.fix.tagNameNumMap`MsgType]: string .fix.msgNameTypeMap`ExecutionReport;
    message[.fix.tagNameNumMap`OrderID]: "ORDER2015.04.04";
    message[.fix.tagNameNumMap`ExecID]: "ORDER2015.04.04";
    message[.fix.tagNameNumMap`ExecType]: enlist "0";
    message[.fix.tagNameNumMap`OrdStatus]: enlist "0";
    message[.fix.tagNameNumMap`Symbol]: "TESTSYM";
    message[.fix.tagNameNumMap`Side]: enlist "1";
    message[.fix.tagNameNumMap`LeavesQty]: 123.4;
    message[.fix.tagNameNumMap`CumQty]: 876.0;
    message[.fix.tagNameNumMap`AvgPx]: 1.38;
    .fix.send[message];
   }
q)
```


## Repeating groups in the FIX protocol

Sometimes we need to represent array-like data structures within a FIX message. One of the more intuitive examples is sending an order to a broker to execute a two-legged strategy. How can we embed the symbology, order quantities and other information of the two legs in the flat message structure of the FIX protocol if they use the same tags?
The FIX protocol achieves this via the concept of ‘Repeating groups’. For any ‘repeatable’ collections of tags that we may need to define in our messages (be it for defining multiple legs, market depth levels, etc.), the data dictionary of our chosen FIX specification will define a field of type `NUMINGROUP`. This NUMINGROUP field is placed before the repeated groups of tags in the message and denotes how many repetitions of the group occur.

Let’s take our two-legged order example. Implementations vary across brokerages, but let’s assume that our chosen broker adheres to the 4.4 FIX specification and insists that multi-leg orders should be structured with the `UnderlyingInstrument` repeating group (NUMINGROUP tag: 711).

To send a multi-legged market order, the broker specifies that that we need to define at a minimum the `UnderlyingSymbol` (311) and `UnderlyingQty` (389) for each leg. Our FIX message would be structured as follows:


```
8=FIX.4.4�9=227�35=D�34=4�49=CTRE�52=20220317-18:00:51.599�56=BROKER�11=SHD2020.03.17�21=2�38=876.0�40=1�54=2�55=TESTSYM�60=20220317-14:21:36.567�711=2�311=SYMBOL1�879=876.0�311=SYMBOL2�879=877.0�10=101�
```


The 711=2 (`NoUnderlyings`) denotes that two instances of the `UnderlyingInstrument` group are encoded in the message immediately after that field. The FIX protocol interprets each ensuing field to be a member of the same group instance until a repeated tag is encountered (i.e.: the second instance of the 311 tag above); when this happens it is interpreted as the start of a new instance of the group. This continues until the protocol encounters a field that is not defined in the repeating group as per the data dictionary (i.e.: in our example above, fields follow the second 879 tag instance are taken to be part of the top level of the message). For these reasons the FIX protocol (and by extension the QuickFIX engine) enforces that the tag order of any repeating groups you set in a message matches the order in the data dictionary for your FIX specification.

For clarity, the `NUMINGROUP` field of a repeating group will be used to refer to the repeating group as a whole in the following examples.

## Sending a FIX message with repeating groups from kdb+

The [ccjtre/kdb-fix-adaptor library](https://github.com/ccjtre/kdb-fix-adaptor) extends the original AquaQ library by offering support for sending and receiving repeating groups. The first question to ask before sending a FIX message with repeating groups from kdb+ is: How can we model them in the kdb+ dictionary representation of our message? The library represents each instance of the repeating group as another dictionary and associates a list of these dictionaries to the corresponding `NUMINGROUP` tag in the parent dictionary. Using this method let’s construct a slightly more complex multi-legged `NewOrderSingle` example:


```q
/ initiator

q).fix.sendNewOrderSingleWithUnderlyings
{[]
    message:()!();
    message[.fix.tagNameNumMap`BeginString]: "FIX.4.4";
    message[.fix.tagNameNumMap`SenderCompID]: string .fix.session.senderCompID;
    message[.fix.tagNameNumMap`TargetCompID]: string .fix.session.targetCompID;
    message[.fix.tagNameNumMap`MsgType]: string .fix.msgNameTypeMap`NewOrderSingle;
    message[.fix.tagNameNumMap`ClOrdID]: "SHD2015.04.04";
    message[.fix.tagNameNumMap`Symbol]: "TESTSYM";
    message[.fix.tagNameNumMap`Side]: enlist "2";
    message[.fix.tagNameNumMap`HandlInst]: enlist "2";
    message[.fix.tagNameNumMap`TransactTime]: 2016.03.04D14:21:36.567000000;
    message[.fix.tagNameNumMap`OrdType]: enlist "1";

    underlyingInst1:.fix.tagNameNumMap[`UnderlyingSymbol`UnderlyingQty`UnderlyingStartValue]!("SYMBOL1";"876.0";"876.0");
    underlyingInst2:.fix.tagNameNumMap[`UnderlyingSymbol`UnderlyingQty]!("SYMBOL2";"877.0");
    message[.fix.tagNameNumMap`NoUnderlyings]:(underlyingInst1; underlyingInst2);

    partiesInst1:.fix.tagNameNumMap[`PartyID`PartyIDSource]!("BRIAN";enlist "C");
    partiesInst2:.fix.tagNameNumMap[`PartyID`PartyIDSource]!("ACME";enlist "C");
    message[.fix.tagNameNumMap`NoPartyIDs]:(partiesInst1; partiesInst2);

    message[.fix.tagNameNumMap`OrderQty]: "876.0";

    .fix.send[message];
    }
q).fix.sendNewOrderSingleWithUnderlyings[]

/ acceptor

8  | "FIX.4.4" / NewOrderSingle received from initiator
9  | 228f
35 | ,"D"
34 | 11i
49 | "CTRE"
52 | 2022.03.21D14:33:06.335000064
56 | "BROKER"
11 | "SHD2015.04.04"
21 | "2"
38 | 876f
40 | "1"
54 | "2"
55 | "TESTSYM"
60 | 2016.03.04D14:21:36.567000000
453| (448 447!("BRIAN";"C");448 447!("ACME";"C"))
711| (311 879 884!("SYMBOL1";876f;876f);311 879!("SYMBOL2";877f))
10 | "133"

/ FIX message sent by initiator:
20220321-14:49:49.597844000 : 8=FIX.4.49=22735=D34=249=CTRE52=20220321-14:49:49.59756=BROKER11=SHD2015.04.0421=238=876.040=154=255=TESTSYM60=20160304-14:21:36.567453=2448=BRIAN447=C448=ACME447=C711=2311=SYMBOL1879=876.0884=876.0311=SYMBOL2879=877.010=108
```


Note that the library support asymmetric instances in the same repeating group provided that tag order adheres to the data dictionary: in the above example we’ve included an additional `UnderlyingStartValue` field in the first instance of the `NoUnderlyings` (711) group. Also note that multiple repeating groups in the same message are supported: see the addition of the `NoPartyIDs` (453) repeating group. The message can then be passed to `.fix.send` in the same way as before.

A more common use case of repeating groups in the FIX protocol is in the [`MarketDataRequest` (`MsgType`=V) message type](https://www.onixs.biz/fix-dictionary/4.4/msgType_V_86.html). This message contains the mandatory `NoMDEntryTypes` (267) tag which denotes the number of `MDEntryType` (269) elements in the request. The `MDEntryType` elements in turn determine the types of market data entries that the requestor is interested in. The example below demonstrates requesting the current snapshot of the top-of-book bid and ask for a single currency pair, and responding to the request with a `MarketDataSnapshotFullRefresh` (`MsgType`=W):


```q
/ initiator

q).fix.sendMarketDataRequest
{[]
    message:()!();
    message[.fix.tagNameNumMap`BeginString]: "FIX.4.4";
    message[.fix.tagNameNumMap`SenderCompID]: string .fix.session.senderCompID;
    message[.fix.tagNameNumMap`TargetCompID]: string .fix.session.targetCompID;
    message[.fix.tagNameNumMap`MsgType]: string .fix.msgNameTypeMap`MarketDataRequest;
    message[.fix.tagNameNumMap`MDReqID]: "MarketDataRequest01";
    message[.fix.tagNameNumMap`SubscriptionRequestType]: enlist "0"; // request snapshot
    message[.fix.tagNameNumMap`MarketDepth]: 1; // request top of book
    mdEntryTypeInst1: enlist[.fix.tagNameNumMap`MDEntryType]!enlist enlist "0";
    mdEntryTypeInst2: enlist[.fix.tagNameNumMap`MDEntryType]!enlist enlist "1";
    message[.fix.tagNameNumMap`NoMDEntryTypes]: (mdEntryTypeInst1;mdEntryTypeInst2); // request bid and offer
    relatedSymInst1: enlist[.fix.tagNameNumMap`Symbol]!enlist "EUR/USD";
    message[.fix.tagNameNumMap`NoRelatedSym]: enlist relatedSymInst1; // request is for one sym only
    .fix.send[message];
    }
q)
q).fix.sendMarketDataRequest[]
q)8  | "FIX.4.4" / MarketDataSnapshotFullRefresh received from acceptor
9  | 139f
35 | ,"W"
34 | 14i
49 | "CTRE"
52 | 2022.03.21D14:37:34.348999936
56 | "BROKER"
55 | "EUR/USD"
262| "MarketDataRequest01"
268| (269 270 271!("0";1.1;100f);269 270 271!("1";1.11;90f))
10 | "224"

/ acceptor

q)8  | "FIX.4.4" / MarketDataRequest received from initiator
9  | 125f
35 | ,"V"
34 | 14i
49 | "BROKER"
52 | 2022.03.21D14:37:34.347000064
56 | "CTRE"
262| "MarketDataRequest01"
263| "0"
264| 1i
146| ,(,55)!,"EUR/USD"
267| ((,269)!,"0";(,269)!,"1")
10 | "076"

q).fix.sendMarketDataSnapShotFullRefresh / callback invoked on receipt of MarketDataRequest
{[x]
    if[.fix.mode=`replay;:()];
    message:()!();
    message[.fix.tagNameNumMap`BeginString]: "FIX.4.4";
    message[.fix.tagNameNumMap`SenderCompID]: x[.fix.tagNameNumMap`TargetCompID];
    message[.fix.tagNameNumMap`TargetCompID]: x[.fix.tagNameNumMap`SenderCompID];
    message[.fix.tagNameNumMap`MsgType]: string .fix.msgNameTypeMap`MarketDataSnapshotFullRefresh;
    message[.fix.tagNameNumMap`MDReqID]: x[.fix.tagNameNumMap`MDReqID];
    message[.fix.tagNameNumMap`Symbol]: "EUR/USD";
    mdEntryInst1: .fix.tagNameNumMap[`MDEntryType`MDEntryPx`MDEntrySize]!(enlist "0";1.10;100); / best bid
    mdEntryInst2: .fix.tagNameNumMap[`MDEntryType`MDEntryPx`MDEntrySize]!(enlist "1";1.11;90); / best offer
    message[.fix.tagNameNumMap`NoMDEntries]: (mdEntryInst1;mdEntryInst2);
    .fix.send[message];
    }

```

## Sending a FIX message with nested repeating groups from kdb+

The FIX protocol also allows for arbitrary levels of nesting in repeating groups, although in practice this tends not to exceed 3 to 4 levels of depth. A very common example is a repeating group of Party sub-identifiers (`NoPartySubIDs` (802)) within a `NoParties` (453) block. The library offers support for nested repeating groups of arbitrary depth. The `.fix.sendNewOrderSingleWithSubParties` function in `fix.q` shows an example of sending this nested party information on a `NewOrderSingle`:


```q
/ initiator

q).fix.sendNewOrderSingleWithSubParties
{[]
    message:()!();
    message[.fix.tagNameNumMap`BeginString]: "FIX.4.4";
    message[.fix.tagNameNumMap`SenderCompID]: string .fix.session.senderCompID;
    message[.fix.tagNameNumMap`TargetCompID]: string .fix.session.targetCompID;
    message[.fix.tagNameNumMap`MsgType]: string .fix.msgNameTypeMap`NewOrderSingle;
    message[.fix.tagNameNumMap`ClOrdID]: "SHD2015.04.04";
    message[.fix.tagNameNumMap`Symbol]: "TESTSYM";
    message[.fix.tagNameNumMap`Side]: enlist "2";
    message[.fix.tagNameNumMap`HandlInst]: enlist "2";
    message[.fix.tagNameNumMap`TransactTime]: 2016.03.04D14:21:36.567000000;
    message[.fix.tagNameNumMap`OrdType]: enlist "1";

    subPartiesInst1A:.fix.tagNameNumMap[`PartySubID`PartySubIDType]!("aine";enlist "2");
    subPartiesInst1B:.fix.tagNameNumMap[`PartySubID`PartySubIDType]!("a@firm.com";enlist "8");
    partiesInst1:.fix.tagNameNumMap[`PartyID`PartyIDSource`PartyRole`NoPartySubIDs]!("AINE";enlist "C";enlist "3";(subPartiesInst1A; subPartiesInst1B));

    subPartiesInst2A:.fix.tagNameNumMap[`PartySubID`PartySubIDType]!("acme";enlist "1");
    subPartiesInst2B:.fix.tagNameNumMap[`PartySubID`PartySubIDType]!("IE";"18");
    partiesInst2:.fix.tagNameNumMap[`PartyID`PartyIDSource`PartyRole`NoPartySubIDs]!("ACME";enlist "C";"13";(subPartiesInst2A; subPartiesInst2B));

    message[.fix.tagNameNumMap`NoPartyIDs]: (partiesInst1; partiesInst2);
    message[.fix.tagNameNumMap`OrderQty]: "876.0";

    .fix.send[message];
    }
q)
q).fix.sendNewOrderSingleWithSubParties[]

/ acceptor

8  | "FIX.4.4"  / NewOrderSingle received from initiator
9  | 257f
35 | ,"D"
34 | 17i
49 | "BROKER"
52 | 2022.03.21D14:41:42.692000000
56 | "CTRE"
11 | "SHD2015.04.04"
21 | "2"
38 | 876f
40 | "1"
54 | "2"
55 | "TESTSYM"
60 | 2016.03.04D14:21:36.567000000
453| (448 447 452 802!("AINE";"C";3i;(523 803!("aine";2i);523 803!("a@firm.com";8i)));448 447 452 802!("ACME";"C";13i;(523 803!("acme";1i);523 803!("IE";18i))))
10 | "111"

```

## Replaying a FIX message log in kdb+

A FIX log can be replayed into a kdb+ session by first initializing an acceptor and then calling the `.fix.replay` function with two arguments: the FIX data dictionary to validate the messages against and the log itself. This will convert the string representation of each FIX message to a q dictionary and append said dictionary to `.fix.recvMsgs`. Note that an active counterparty is not needed on the session to replay the log. The `.fix.replay` function will account for any nested repeating groups in the log provided that they adhere to the data dictionary supplied.


```txt
cat /var/tmp/quickfix/log/FIX.4.4-CTRE-BROKER.messages.current.log
20220317-18:00:25.528573000 : 8=FIX.4.4�9=66�35=A�34=1�49=CTRE�52=20220317-18:00:25.528�56=BROKER�98=0�108=120�10=037�
20220317-18:00:25.529219000 : 8=FIX.4.4�9=66�35=A�34=1�49=BROKER�52=20220317-18:00:25.529�56=CTRE�98=0�108=120�10=038�
20220317-18:00:31.734226000 : 8=FIX.4.4�9=130�35=D�34=2�49=CTRE�52=20220317-18:00:31.733�56=BROKER�11=SHD2015.04.04�21=2�38=876.0�40=1�54=2�55=TESTSYM�60=20160304-14:21:36.567�10=080�
20220317-18:00:31.743116000 : 8=FIX.4.4�9=142�35=8�34=2�49=BROKER�52=20220317-18:00:31.742�56=CTRE�6=1.38�14=876�17=ORDER2015.04.04�37=ORDER2015.04.04�39=0�54=1�55=TESTSYM�150=0�151=123.4�10=002�
20220317-18:00:45.516474000 : 8=FIX.4.4�9=256�35=D�34=3�49=CTRE�52=20220317-18:00:45.505�56=BROKER�11=SHD2015.04.04�21=2�38=876.0�40=1�54=2�55=TESTSYM�60=20160304-14:21:36.567�453=2�448=AINE�447=C�452=3�802=2�523=aine�803=2�523=a@firm.com�803=8�448=ACME�447=C�452=13�802=2�523=acme�803=1�523=IE�803=18�10=057�
20220317-18:00:45.570695000 : 8=FIX.4.4�9=142�35=8�34=3�49=BROKER�52=20220317-18:00:45.567�56=CTRE�6=1.38�14=876�17=ORDER2015.04.04�37=ORDER2015.04.04�39=0�54=1�55=TESTSYM�150=0�151=123.4�10=013�
20220317-18:00:51.599256000 : 8=FIX.4.4�9=227�35=D�34=4�49=CTRE�52=20220317-18:00:51.599�56=BROKER�11=SHD2015.04.04�21=2�38=876.0�40=1�54=2�55=TESTSYM�60=20160304-14:21:36.567�453=2�448=BRIAN�447=C�448=ACME�447=C�711=2�311=SYMBOL1�879=876.0�884=876.0�311=SYMBOL2�879=877.0�10=101�
20220317-18:00:51.609351000 : 8=FIX.4.4�9=142�35=8�34=4�49=BROKER�52=20220317-18:00:51.608�56=CTRE�6=1.38�14=876�17=ORDER2015.04.04�37=ORDER2015.04.04�39=0�54=1�55=TESTSYM�150=0�151=123.4�10=007�
20220317-18:00:58.103464000 : 8=FIX.4.4�9=124�35=V�34=5�49=CTRE�52=20220317-18:00:58.103�56=BROKER�146=1�55=EUR/USD�262=MarketDataRequest01�263=0�264=1�267=2�269=0�269=1�10=022�
20220317-18:00:58.120536000 : 8=FIX.4.4�9=138�35=W�34=5�49=BROKER�52=20220317-18:00:58.120�56=CTRE�55=EUR/USD�262=MarketDataRequest01�268=2�269=0�270=1.1�271=100�269=�270=1.11�271=90�10=167�
```



```q
q).fix.init[`BROKER;`CTRE;`acceptor;`:src/config/sessions/sample.ini;`:src/config/spec/FIX44.xml]
GetKMaps - Loading src/config/spec/FIX44.xml
CreateFIXMaps - Loading src/config/spec/FIX44.xml
Creating Acceptor
q).fix.replay[`:src/config/spec/FIX44.xml;hsym `$"/var/tmp/quickfix/log/FIX.4.4-CTRE-BROKER.messages.current.log"]
q)8  | "FIX.4.4"
9  | 66f
35 | ,"A"
34 | 1i
49 | "CTRE"
52 | 2022.03.17D18:00:25.528000000
56 | "BROKER"
98 | 0i
108| 120i
10 | "037"
8  | "FIX.4.4"
9  | 66f
35 | ,"A"
34 | 1i
49 | "BROKER"
52 | 2022.03.17D18:00:25.528999936
56 | "CTRE"
98 | 0i
108| 120i
10 | "038"
8 | "FIX.4.4"
9 | 130f
35| ,"D"
34| 2i
49| "CTRE"
52| 2022.03.17D18:00:31.732999936
56| "BROKER"
11| "SHD2015.04.04"
21| "2"
38| 876f
40| "1"
54| "2"
55| "TESTSYM"
60| 2016.03.04D14:21:36.567000000
10| "080"
...

q).fix.recvMsgs
8 9 35 34 49 52 56 98 108 10!("FIX.4.4";66f;,"A";1i;"CTRE";2022.03.17D18:00:25.528000000;"BROKER";0i;120i;"037")
8 9 35 34 49 52 56 98 108 10!("FIX.4.4";66f;,"A";1i;"BROKER";2022.03.17D18:00:25.528999936;"CTRE";0i;120i;"038")
8 9 35 34 49 52 56 11 21 38 40 54 55 60 10!("FIX.4.4";130f;,"D";2i;"CTRE";2022.03.17D18:00:31.732999936;"BROKER";"SHD2015.04.04";"2";876f;"1";"2";"TESTSYM";2016.03.04D14:21:36.567000000;"080")
8 9 35 34 49 52 56 6 14 17 37 39 54 55 150 151 10!("FIX.4.4";142f;,"8";2i;"BROKER";2022.03.17D18:00:31.742000000;"CTRE";1.38;876f;"ORDER2015.04.04";"ORDER2015.04.04";"0";"1";"TESTSYM";"0";123.4;"002")
8 9 35 34 49 52 56 11 21 38 40 54 55 60 453 10!("FIX.4.4";256f;,"D";3i;"CTRE";2022.03.17D18:00:45.504999936;"BROKER";"SHD2015.04.04";"2";876f;"1";"2";"TESTSYM";2016.03.04D14:21:36.567000000;(448 447 452 802!("AINE";"C";3i;(523 803!("aine";2i);523 803!("a@firm.com";8i)));448 447 452 802!("ACME";"C";13i;(523 803!("acme";1i);523 803!("IE";18i))));"057")
8 9 35 34 49 52 56 6 14 17 37 39 54 55 150 151 10!("FIX.4.4";142f;,"8";3i;"BROKER";2022.03.17D18:00:45.567000064;"CTRE";1.38;876f;"ORDER2015.04.04";"ORDER2015.04.04";"0";"1";"TESTSYM";"0";123.4;"013")
8 9 35 34 49 52 56 11 21 38 40 54 55 60 453 711 10!("FIX.4.4";227f;,"D";4i;"CTRE";2022.03.17D18:00:51.599000064;"BROKER";"SHD2015.04.04";"2";876f;"1";"2";"TESTSYM";2016.03.04D14:21:36.567000000;(448 447!("BRIAN";"C");448 447!("ACME";"C"));(311 879 884!("SYMBOL1";876f;876f);311 879!("SYMBOL2";877f));"101")
8 9 35 34 49 52 56 6 14 17 37 39 54 55 150 151 10!("FIX.4.4";142f;,"8";4i;"BROKER";2022.03.17D18:00:51.608000000;"CTRE";1.38;876f;"ORDER2015.04.04";"ORDER2015.04.04";"0";"1";"TESTSYM";"0";123.4;"007")
8 9 35 34 49 52 56 262 263 264 146 267 10!("FIX.4.4";124f;,"V";5i;"CTRE";2022.03.17D18:00:58.103000064;"BROKER";"MarketDataRequest01";"0";1i;,(,55)!,"EUR/USD";((,269)!,"0";(,269)!,"1");"022")
8 9 35 34 49 52 56 55 262 268 10!("FIX.4.4";138f;,"W";5i;"BROKER";2022.03.17D18:00:58.120000000;"CTRE";"EUR/USD";"MarketDataRequest01";(269 270 271!("0";1.1;100f);269 270 271!("1";1.11;90f));"167")
```


## Summary

This article has outlined how kdb+ has been interfaced with the FIX protocol in the past, from Damien Barker’s whitepaper which demonstrated calculating order state from an OMS FIX message stream to AquaQ’s QuickFIX-kdb adaptor. The FIX message format and the QuickFIX engine were discussed before we took a deep dive into how AquaQ’s solution was extended to manage repeating groups in the FIX protocol. Worked examples of using repeating groups included embedding symbology for multiple instruments in a `NewOrderSingle`, sending and fulfilling market data requests between counterparties, nesting party information on a `NewOrderSingle`, and replaying FIX message logs containing nested information into a kdb+ session.
