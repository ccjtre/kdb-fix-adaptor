.fix:(`:./@BINARY_NAME@ 2:(`LoadLibrary;1))`

/// configs

.fix.session.senderCompID:`;
.fix.session.targetCompID:`;
.fix.tagNameNumMap:(`symbol$())!`long$();
.fix.msgNameTypeMap:(`symbol$())!`long$();
.fix.mode:`session; / `replay
.fix.updMap:(!) . flip (
    (`D;`.fix.sendExecutionReport);
    (`V;`.fix.sendMarketDataSnapShotFullRefresh)
    );

.fix.recvMsgs:();

/// init

.fix.init:{[senderCompID;targetCompID;counterPartyType;configFile;dataDictFile]
    .fix.session.senderCompID:senderCompID;
    .fix.session.targetCompID:targetCompID;
    m:.fix.getKMaps[dataDictFile];
    .fix.tagNameNumMap:m 0;
    .fix.msgNameTypeMap:m 1;
    .fix.create[counterPartyType;configFile;dataDictFile];
  }

/// functions

.fix.onRecv:{[x] 
    show x;
    .fix.recvMsgs,:enlist x;
    value (`.fix.defaultHandler^.fix.updMap[`$x 35] x; x);
  }

.fix.defaultHandler:{[x]
    (::)
  }

.fix.replay:{[dataDictFile;fixLogFile]
    .fix.mode:`replay;
    .[.fix.replayFIXLog;(dataDictFile;fixLogFile);{.fix.mode:`session;'x}];
    .fix.mode:`session;
  }

// examples

/ linear messages

.fix.sendNewOrderSingle:{[]
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

.fix.sendExecutionReport:{[x]
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

/ nested groups

.fix.sendMarketDataRequest:{[]
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

.fix.sendMarketDataSnapShotFullRefresh:{[x]
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

.fix.sendNewOrderSingleWithUnderlyings:{[]
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

.fix.sendNewOrderSingleWithSubParties:{[]
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
