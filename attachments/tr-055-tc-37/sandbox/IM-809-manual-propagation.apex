// Plan B: simulate post-propagation state directly on Sale_Item.
// If SaleItem_Trg resets these on update, we'll see them revert. If they stick, we have the demo state.

Id siId = [SELECT Id FROM Auctifera__Sale_Item__c WHERE Auctifera__External_Id__c = 'IM-809-SI-001'].Id;

Auctifera__Sale_Item__c si = new Auctifera__Sale_Item__c(
    Id = siId,
    Auctifera__Discount_Type__c = 'Amount',
    Auctifera__Discount_Value__c = 1.80,
    Auctifera__Discount_Amount__c = -1.80,
    Auctifera__Price_Without_Tax__c = 16.20,
    Auctifera__Amount__c = 17.86,
    Auctifera__Tax_Amount__c = 1.66
);
update si;

Auctifera__Sale_Item__c siAfter = [SELECT Auctifera__Item_Price__c, Auctifera__Price_Without_Tax__c, Auctifera__Amount__c, Auctifera__Discount_Type__c, Auctifera__Discount_Value__c, Auctifera__Discount_Amount__c, Auctifera__Tax_Amount__c FROM Auctifera__Sale_Item__c WHERE Id = :siId];
System.debug('SI after manual update: price=' + siAfter.Auctifera__Item_Price__c + ' net=' + siAfter.Auctifera__Price_Without_Tax__c + ' amount=' + siAfter.Auctifera__Amount__c + ' discType=' + siAfter.Auctifera__Discount_Type__c + ' discValue=' + siAfter.Auctifera__Discount_Value__c + ' discAmt=' + siAfter.Auctifera__Discount_Amount__c + ' tax=' + siAfter.Auctifera__Tax_Amount__c);

Auctifera__ClientPurchase__c cp = [SELECT Auctifera__Total__c, Auctifera__Total2__c, Auctifera__Subtotal__c, Auctifera__Subtotal_before_discount__c, Auctifera__Total_Discount_Amount__c, Auctifera__Total_Discount_Amount_2__c FROM Auctifera__ClientPurchase__c WHERE Auctifera__Transaction_Id__c = 'IM-809-CP-001'];
System.debug('CP after manual SI update: Total=' + cp.Auctifera__Total__c + ' Total2=' + cp.Auctifera__Total2__c + ' Sub=' + cp.Auctifera__Subtotal__c + ' SubBeforeDisc=' + cp.Auctifera__Subtotal_before_discount__c + ' TotalDisc=' + cp.Auctifera__Total_Discount_Amount__c + ' TotalDisc2=' + cp.Auctifera__Total_Discount_Amount_2__c);

Auctifera__POS_Purchase__c pp = [SELECT Auctifera__Total__c, Auctifera__Subtotal__c, Auctifera__Shop_Discount_Amount__c FROM Auctifera__POS_Purchase__c WHERE Auctifera__Implementation_External_ID__c = 'IM-809-POSPURCH-001'];
System.debug('PP: Total=' + pp.Auctifera__Total__c + ' Sub=' + pp.Auctifera__Subtotal__c + ' ShopDisc=' + pp.Auctifera__Shop_Discount_Amount__c);
