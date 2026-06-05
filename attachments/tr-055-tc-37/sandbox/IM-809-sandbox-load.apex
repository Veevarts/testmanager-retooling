// IM-809 sandbox fixture: replicate the PR 121 post-fix state for Altru SALESORDER 12520367 -> P-30881.
// Expected after trigger ClientPurchaseTriggerHandler.propagateDiscount fires:
//   Sale_Item.Price_Without_Tax = 16.20, Sale_Item.Amount = 17.86
//   ClientPurchase.Total2 = 17.86

System.debug('=== IM-809 sandbox fixture start ===');

// 1) Catalog Item (parent for Sale Item)
Auctifera__CatalogItem__c ci = new Auctifera__CatalogItem__c(
    Name = 'IM-809 Test Item (Shop Merch $18)',
    Auctifera__Price__c = 18.00,
    Auctifera__Product_ID__c = 'IM-809-PROD-001',
    Auctifera__Implementation_External_ID__c = 'IM-809-CI-001'
);
insert ci;
System.debug('Created CatalogItem: ' + ci.Id);

// 2) POS Purchase (parent for ClientPurchase + POS_Discount)
Id anonContact = [SELECT Id FROM Contact WHERE Name = 'Anonymous Contact' LIMIT 1].Id;
Id testAccount = [SELECT Id FROM Account WHERE Name = 'Test Org' LIMIT 1].Id;
Auctifera__POS_Purchase__c pp = new Auctifera__POS_Purchase__c(
    Auctifera__Client__c = anonContact,
    Auctifera__Client2__c = testAccount,
    Auctifera__Implementation_External_ID__c = 'IM-809-POSPURCH-001',
    Auctifera__Transaction_Id__c = 'IM-809-TXN-001'
);
insert pp;
System.debug('Created POS_Purchase: ' + pp.Id);

// 3) ClientPurchase linked to POS_Purchase
Auctifera__ClientPurchase__c cp = new Auctifera__ClientPurchase__c(
    Auctifera__POS_Purchase__c = pp.Id,
    Auctifera__Transaction_Id__c = 'IM-809-CP-001'
);
insert cp;
System.debug('Created ClientPurchase: ' + cp.Id);

// 4) Sale Item with Item_Price = $18.00 GROSS (post-PR behavior); Tax = 10.25%
Auctifera__Sale_Item__c si = new Auctifera__Sale_Item__c(
    Auctifera__Client_Purchase__c = cp.Id,
    Auctifera__Catalog_Item__c = ci.Id,
    Auctifera__Item_Price__c = 18.00,
    Auctifera__Number_of_Items_bought__c = 1,
    Auctifera__Tax_2__c = 10.25,
    Auctifera__External_Id__c = 'IM-809-SI-001'
);
insert si;
System.debug('Created Sale_Item: ' + si.Id);

// 5) State BEFORE POS_Discount insert
Auctifera__Sale_Item__c siBefore = [
    SELECT Auctifera__Item_Price__c, Auctifera__Price_Without_Tax__c, Auctifera__Amount__c,
           Auctifera__Discount_Type__c, Auctifera__Discount_Value__c, Auctifera__Discount_Amount__c, Auctifera__Tax_Amount__c
    FROM Auctifera__Sale_Item__c WHERE Id = :si.Id
];
Auctifera__ClientPurchase__c cpBefore = [
    SELECT Auctifera__Total__c, Auctifera__Total2__c, Auctifera__Subtotal__c, Auctifera__Subtotal_before_discount__c,
           Auctifera__Total_Discount_Amount__c, Auctifera__Total_Discount_Amount_2__c
    FROM Auctifera__ClientPurchase__c WHERE Id = :cp.Id
];
System.debug('SI BEFORE: price=' + siBefore.Auctifera__Item_Price__c
    + ' net=' + siBefore.Auctifera__Price_Without_Tax__c
    + ' amount=' + siBefore.Auctifera__Amount__c
    + ' discType=' + siBefore.Auctifera__Discount_Type__c
    + ' discValue=' + siBefore.Auctifera__Discount_Value__c
    + ' discAmt=' + siBefore.Auctifera__Discount_Amount__c
    + ' tax=' + siBefore.Auctifera__Tax_Amount__c);
System.debug('CP BEFORE: Total=' + cpBefore.Auctifera__Total__c
    + ' Total2=' + cpBefore.Auctifera__Total2__c
    + ' Subtotal=' + cpBefore.Auctifera__Subtotal__c
    + ' SubBeforeDisc=' + cpBefore.Auctifera__Subtotal_before_discount__c
    + ' TotalDisc=' + cpBefore.Auctifera__Total_Discount_Amount__c
    + ' TotalDisc2=' + cpBefore.Auctifera__Total_Discount_Amount_2__c);

// 6) POS_Discount: Value=18, Discount_Type='Amount', Discount_Value=1.80, Discount_Amount=-1.80, Discount_Source='Custom'
Auctifera__POS_Discount__c pd = new Auctifera__POS_Discount__c(
    Auctifera__POS_Purchase__c = pp.Id,
    Auctifera__Purchase__c = cp.Id,
    Auctifera__POS_Purchase_Subtotal__c = 18.00,
    Auctifera__Discount_Type__c = 'Amount',
    Auctifera__Discount_Value__c = 1.80,
    Auctifera__Discount_Amount__c = -1.80,
    Auctifera__Discount_Source__c = 'Custom',
    Auctifera__Implementation_External_ID__c = 'IM-809-POSDISC-001'
);
insert pd;
System.debug('Created POS_Discount: ' + pd.Id);

// 7) State AFTER POS_Discount insert (trigger should have fired)
Auctifera__Sale_Item__c siAfter = [
    SELECT Auctifera__Item_Price__c, Auctifera__Price_Without_Tax__c, Auctifera__Amount__c,
           Auctifera__Discount_Type__c, Auctifera__Discount_Value__c, Auctifera__Discount_Amount__c, Auctifera__Tax_Amount__c
    FROM Auctifera__Sale_Item__c WHERE Id = :si.Id
];
Auctifera__ClientPurchase__c cpAfter = [
    SELECT Auctifera__Total__c, Auctifera__Total2__c, Auctifera__Subtotal__c, Auctifera__Subtotal_before_discount__c,
           Auctifera__Total_Discount_Amount__c, Auctifera__Total_Discount_Amount_2__c
    FROM Auctifera__ClientPurchase__c WHERE Id = :cp.Id
];
System.debug('SI AFTER : price=' + siAfter.Auctifera__Item_Price__c
    + ' net=' + siAfter.Auctifera__Price_Without_Tax__c
    + ' amount=' + siAfter.Auctifera__Amount__c
    + ' discType=' + siAfter.Auctifera__Discount_Type__c
    + ' discValue=' + siAfter.Auctifera__Discount_Value__c
    + ' discAmt=' + siAfter.Auctifera__Discount_Amount__c
    + ' tax=' + siAfter.Auctifera__Tax_Amount__c);
System.debug('CP AFTER : Total=' + cpAfter.Auctifera__Total__c
    + ' Total2=' + cpAfter.Auctifera__Total2__c
    + ' Subtotal=' + cpAfter.Auctifera__Subtotal__c
    + ' SubBeforeDisc=' + cpAfter.Auctifera__Subtotal_before_discount__c
    + ' TotalDisc=' + cpAfter.Auctifera__Total_Discount_Amount__c
    + ' TotalDisc2=' + cpAfter.Auctifera__Total_Discount_Amount_2__c);

System.debug('=== IDs ===');
System.debug('CatalogItem    : ' + ci.Id);
System.debug('POS_Purchase   : ' + pp.Id);
System.debug('ClientPurchase : ' + cp.Id);
System.debug('Sale_Item      : ' + si.Id);
System.debug('POS_Discount   : ' + pd.Id);

System.debug('=== EXPECTED ===');
System.debug('Sale_Item.Price_Without_Tax should be 16.20 (18.00 - 1.80)');
System.debug('Sale_Item.Amount should be 17.86 (16.20 + 10.25% tax)');
System.debug('ClientPurchase.Total2 should be 17.86 (rollup from Sale Items)');
