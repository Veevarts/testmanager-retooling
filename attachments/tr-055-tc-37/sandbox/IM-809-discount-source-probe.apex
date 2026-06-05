// Probe: cycle Discount_Source through all picklist values and observe Sale_Item propagation.

Id pdId = [SELECT Id FROM Auctifera__POS_Discount__c WHERE Auctifera__Implementation_External_ID__c = 'IM-809-POSDISC-001'].Id;
Id siId = [SELECT Id FROM Auctifera__Sale_Item__c WHERE Auctifera__External_Id__c = 'IM-809-SI-001'].Id;

for (String src : new List<String>{'Manual', 'Applied', 'Fundraising Events Online', 'Custom'}) {
    Auctifera__POS_Discount__c pd = new Auctifera__POS_Discount__c(Id = pdId, Auctifera__Discount_Source__c = src);
    update pd;
    Auctifera__Sale_Item__c si = [SELECT Auctifera__Price_Without_Tax__c, Auctifera__Amount__c, Auctifera__Discount_Type__c, Auctifera__Discount_Value__c, Auctifera__Discount_Amount__c FROM Auctifera__Sale_Item__c WHERE Id = :siId];
    System.debug('Source=' + src + ' -> SI: net=' + si.Auctifera__Price_Without_Tax__c + ' amount=' + si.Auctifera__Amount__c + ' discType=' + si.Auctifera__Discount_Type__c + ' discValue=' + si.Auctifera__Discount_Value__c + ' discAmt=' + si.Auctifera__Discount_Amount__c);
}
