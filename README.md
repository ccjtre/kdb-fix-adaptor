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
```

Nested repeated groups are also supported: see the .fix.sendNewOrderSingleWithSubParties function in fix.q for sending a sub party information within a party group.

Note that tag order in repeating groups must match the order specified in your data dictionary.

Helper dictionaries
-------------------

The above examples use two helper dictionaries which are populated when you create an acceptor or initiator instance: .fix.tagNameNumMap, which maps FIX field names to the corresponding numerical tag, and .fix.msgNameTypeMap which maps message type names to their correponding 'MsgType' char value. Both adhere to the data dictionary specified in the .fix.init call.

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
