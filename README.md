# KDB+ FIX Engine

FIX is one of the most common protocols used within the finance industry. This repository provides a shared library
implementation of a FIX engine. The accompanying document also describes how to use this library to communicate with
the FIXimulator tool for testing purposes. The implementation is currently in an alpha state and has not been used in
a production system to date. Bugs and features requests should be made through GitHub.

Installation & Setup
--------------------

### Extra Resources
This project uses CMake 3.2+ to support building across multiple platforms and has been tested on Linux. The CMake toolchain will generate the build artefacts required for your platform automatically.

### KDB+
A recent version of kdb+ (i.e version 3.x) should be used when working with the FIX engine. The free 32-bit version of the software can be downloaded from the [Kx Systems][kxsystemslink] website.

### <img src="docs/icons/linux.png" height="16px"> Building on Linux

Install Quickfix

```sh
$ sudo apt-get install g++ automake libtool libxml2 libxml2-dev
$ git clone https://github.com/quickfix/quickfix
$ cd quickfix
$ ./bootstrap
$ ./configure
$ make
$ sudo make install
```

Install FIX Library

This project provides a simple shell script that will handle the build process for you. It will compile all the artifacts in a /tmp folder and then copy the resulting package into your source directory. You can look at this script for an example of how to run the CMake build process manually. Whilst inside the quickfix repo, run the following.

```sh
$ git clone https://github.com/ccjtre/kdb-fix-adaptor
$ cd kdb-fix-adaptor
$ ./package.sh
```

A successful build will place a .tar.gz file in the fix-build directory that contains the shared object, a q script to load the shared object into the .fix namespace. Unzip this file.


**Note on dynamic exceptions:

In kdb-fix-adapter/src/main.cxx, the dynamic exceptions on lines 54, 55, 57, 127, 132 and 137 have been left in despite being depreciated in the current C++ 11 standard. This is because the parent functions in quickfix, which define the functions, contain exceptions. Therefore, instead of altering a 3rd party library, the depreciation errors that are produced have been suppressed by lines 34, 35 and 142 in order to allow the script to run. The dynamic exceptions and suppressing lines may be removed once quickfix is updated.

### Building for 32 bit

In order to build a 32 bit binary on a 64 bit machine you will need to install the following packages
for Debian/Ubuntu systems (there will be equivalent steps to get a multilib environment set up with
other distributions):

```sh
$ sudo apt-get install gcc-multilib g++-multilib
```

Install Quick Fix (32-bit Build)

Append -m32 to both the compiler and linker flags in quickfix/UnitTest++/Makefile since this is not
handled by the ./configure step. The updated flags should resemble the versions below:

```sh
CXXFLAGS ?= -g -m32 -Wall -W -Winline -Wno-unused-private-field -Wno-overloaded-virtual -ansi
LDFLAGS ?= -m32
```

Then at the configure step for the quickfix library, you can pass in some flags to build and install
the 32 bit versions of the library. If you are building in the same directory as you built the 64 bit
version, then ensure you 'make clean' first:

```sh
make clean
./bootstrap
./configure --build=i686-pc-linux-gnu "CFLAGS=-m32" "CXXFLAGS=-m32" "LDFLAGS=-m32"
make
sudo make install
```

Install FIX Adapter (32-bit Build)

Change the BUILD_x86 option in the CMakeLists.txt from "OFF" to "ON" and then rebuild the package to get
a 32 bit binary.

Starting Servers (Acceptors) and Clients (Initiators)
----------------

The .fix.init function is common to both starting Acceptors and Initiators. 

The Acceptor is the server side component of a FIX engine that provides some sort of service by binding to a port and accepting messages.
To start an acceptor you need to call the .fix.init function with the following arguments:

- senderCompID (sym): The SenderCompID of your acceptor. Should agree with the INI configuration file
- targetCompID (sym): The intended TargetCompID (initiator) for your acceptor. Should agree with the INI configuration file
- counterPartyType (sym): `acceptor
- configFile: the INI configuration file for this FIX session
- dataDictFile: the data dictionary for this FIX session. Should agree with the INI configuration file. This is used to generate helper dictionaries in the q session; the data dictionary used by QuickFIX for validation will be sourced via the INI file.

The .fix.init function called as an acceptor will start a background thread that will receive and validate messages and finally forward them to the .fix.onRecv function if the message is well formed.

```apl
/ q fix.q
q).fix.init[`BROKER;`CTRE;`acceptor;`:src/config/sessions/sample.ini;`:src/config/spec/FIX44.xml]
GetKMaps - Loading src/config/spec/FIX44.xml
CreateFIXMaps - Loading src/config/spec/FIX44.xml
Creating Acceptor
```

The Initiator is the client side component of the FIX engine and is intended to be used to connect to acceptors to send messages. To start an initiator you need to call the .fix.init function. This will create a background thread that will open a socket to the target acceptor and allow you to send/receive messages.

```apl
/ q fix.q
q).fix.init[`CTRE;`BROKER;`initiator;`:src/config/sessions/sample.ini;`:src/config/spec/FIX44.xml]
GetKMaps - Loading src/config/spec/FIX44.xml
CreateFIXMaps - Loading src/config/spec/FIX44.xml
Creating Initiator
```

Sending a FIX Message
--------------------

In order to send a FIX message from an initiator to an acceptor, you can use the .fix.send function. The send is executed synchronously and will either raise a signal upon error, otherwise you can assume that the message has been received successfully by the counterparty.

In order to determine who the message will be sent to, the library will read the contents the message dictionary and look for a session on the same process that matches. The BeginString, SenderCompID and TargetCompID fields must be present in every message for this reason.

```apl
/ Session 1 - Create an Acceptor
/ q fix.q
q).fix.init[`BROKER;`CTRE;`acceptor;`:src/config/sessions/sample.ini;`:src/config/spec/FIX44.xml]
GetKMaps - Loading src/config/spec/FIX44.xml
CreateFIXMaps - Loading src/config/spec/FIX44.xml
Creating Acceptor

/ Session 2 - Create an Initiator
/ q fix.q
q).fix.init[`CTRE;`BROKER;`initiator;`:src/config/sessions/sample.ini;`:src/config/spec/FIX44.xml]
GetKMaps - Loading src/config/spec/FIX44.xml
CreateFIXMaps - Loading src/config/spec/FIX44.xml
Creating Initiator

/ We can create a dictionary
/ containing tags and message values
q) message: (8 11 35 46 ...)!("FIX.4.4";175;enlist "D";enlist "8" ...)
/ Then send it as a message
q) .fix.send[message]
```

Repeating Groups
----------------

We can model repeating groups in the q dictionary representation of our FIX message by mapping a list of dictionaries to the corresponding NUMINGROUP key in our dictionary.
In the example below we send a NewOrderSingle with a 2 underlying legs and 2 parties:

```apl
/ in the initiator

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

/ in the acceptor

q)8  | "FIX.4.4"
9  | 229f
35 | ,"D"
34 | 133i
49 | "CTRE"
52 | 2022.02.28D23:03:30.940000000
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
10 | "189"

```

Nested repeated groups are also supported: see the .fix.sendNewOrderSingleWithSubParties function in fix.q for sending a sub party information within a party group.

Note that tag order in repeating groups must match the order specified in your data dictionary.

Helper dictionaries
-------------------

The above examples use two helper dictionaries which are populated when you create an acceptor or initiator instance: .fix.tagNameNumMap, which maps FIX field names to the corresponding numerical tag, and .fix.msgNameTypeMap which maps message type names to their correponding 'MsgType' char value. Both adhere to the data dictionary specified in the .fix.init call.

FIX log replay
--------------

A FIX log can be replayed in a q session by first initializing an acceptor and then calling the .fix.replay function with two arguments: the FIX data dictionary to validate the messages with and the log itself. This will convert the string representation of each FIX message to a q dictionary and append said dictionary to .fix.recvMsgs. Note that an active counterparty is not needed on the session to replay the log. The .fix.replay function will account for any nested repeating groups in the log provided they adhere to the data dictionary supplied. 

```sh
cat /var/tmp/quickfix/log/FIX.4.4-CTRE-BROKER.messages.current.log
20220317-18:00:25.528573000 : 8=FIX.4.49=6635=A34=149=CTRE52=20220317-18:00:25.52856=BROKER98=0108=12010=037
20220317-18:00:25.529219000 : 8=FIX.4.49=6635=A34=149=BROKER52=20220317-18:00:25.52956=CTRE98=0108=12010=038
20220317-18:00:31.734226000 : 8=FIX.4.49=13035=D34=249=CTRE52=20220317-18:00:31.73356=BROKER11=SHD2015.04.0421=238=876.040=154=255=TESTSYM60=20160304-14:21:36.56710=080
20220317-18:00:31.743116000 : 8=FIX.4.49=14235=834=249=BROKER52=20220317-18:00:31.74256=CTRE6=1.3814=87617=ORDER2015.04.0437=ORDER2015.04.0439=054=155=TESTSYM150=0151=123.410=002
20220317-18:00:45.516474000 : 8=FIX.4.49=25635=D34=349=CTRE52=20220317-18:00:45.50556=BROKER11=SHD2015.04.0421=238=876.040=154=255=TESTSYM60=20160304-14:21:36.567453=2448=AINE447=C452=3802=2523=aine803=2523=a@firm.com803=8448=ACME447=C452=13802=2523=acme803=1523=IE803=1810=057
20220317-18:00:45.570695000 : 8=FIX.4.49=14235=834=349=BROKER52=20220317-18:00:45.56756=CTRE6=1.3814=87617=ORDER2015.04.0437=ORDER2015.04.0439=054=155=TESTSYM150=0151=123.410=013
20220317-18:00:51.599256000 : 8=FIX.4.49=22735=D34=449=CTRE52=20220317-18:00:51.59956=BROKER11=SHD2015.04.0421=238=876.040=154=255=TESTSYM60=20160304-14:21:36.567453=2448=BRIAN447=C448=ACME447=C711=2311=SYMBOL1879=876.0884=876.0311=SYMBOL2879=877.010=101
20220317-18:00:51.609351000 : 8=FIX.4.49=14235=834=449=BROKER52=20220317-18:00:51.60856=CTRE6=1.3814=87617=ORDER2015.04.0437=ORDER2015.04.0439=054=155=TESTSYM150=0151=123.410=007
20220317-18:00:58.103464000 : 8=FIX.4.49=12435=V34=549=CTRE52=20220317-18:00:58.10356=BROKER146=155=EUR/USD262=MarketDataRequest01263=0264=1267=2269=0269=110=022
20220317-18:00:58.120536000 : 8=FIX.4.49=13835=W34=549=BROKER52=20220317-18:00:58.12056=CTRE55=EUR/USD262=MarketDataRequest01268=2269=0270=1.1271=100269=270=1.11271=9010=167
```

```apl
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

Acknowledgements
----------------

This product includes software developed by quickfixengine.org ([http://www.quickfixengine.org/][quickfixlink]).
This software is based on ([pugixml library][pugixmllink]). pugixml is Copyright (C) 2006-2015 Arseny Kapoulkine.

[aquaqwebsite]: http://www.aquaq.co.uk  "AquaQ Analytics Website"
[aquaqresources]: http://www.aquaq.co.uk/resources "AquaQ Analytics Website Resources"
[gitpdfdoc]: https://github.com/AquaQAnalytics/kdb-fix-adaptor/blob/master/docs/FixSharedLibrary.pdf
[quickfixrepo]: https://github.com/quickfix/quickfix/
[quickfixlink]: http://www.quickfixengine.org/ 
[fiximulatorlink]: http://fiximulator.org/
[fiximulatorcode]: https://code.google.com/p/fiximulator/
[pugixmllink]: http://www.pugixml.org/
[kxsystemslink]: http://kx.com/software-download.php
