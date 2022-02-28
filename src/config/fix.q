.fix:(`:./@BINARY_NAME@ 2:(`LoadLibrary;1))`

/// configs

.fix.session.senderCompID:`;
.fix.session.targetCompID:`;
.fix.tagNameNumMap:(`symbol$())!`long$();
.fix.msgNameTypeMap:(`symbol$())!`long$();
.fix.updMap:enlist[`]!enlist (::);

/// init

.fix.init:{[senderCompID;targetCompID;counterPartyType;configFile;dataDictFile]
    .fix.session.senderCompID:senderCompID;
    .fix.session.targetCompID:targetCompID;
    m:.fix.getKMaps[dataDictFile];
    .fix.tagNameNumMap:m 0;
    .fix.msgNameTypeMap:m 1;
    .fix.updMap:.fix.setUpdMap[];
    .fix.create[counterPartyType;configFile;dataDictFile];
  }

/// functions

.fix.setUpdMap:{[]
    (!) . flip (
        (` ;(::));
        (`D;.fix.sendExecutionReport)
        )
  }

.fix.onRecv:{[x] 
    show x;
    .fix.lastRecvMsg:x;
    .fix.updMap[`$x 35] x;
  }

// examples

/ linear messages

.fix.sendNewOrderSingle: {[]
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
    message:()!();
    message[.fix.tagNameNumMap`MsgType]: string .fix.msgNameTypeMap`ExecutionReport;
    message[.fix.tagNameNumMap`BeginString]: "FIX.4.4";
    message[.fix.tagNameNumMap`SenderCompID]: x[.fix.tagNameNumMap`TargetCompID];
    message[.fix.tagNameNumMap`TargetCompID]: x[.fix.tagNameNumMap`SenderCompID];
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

.fix.sendNewOrderSingleWithUnderlyings: {[]
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

.fix.sendNewOrderSingleWithSubParties: {[]
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
