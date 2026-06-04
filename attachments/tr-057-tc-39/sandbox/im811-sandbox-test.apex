Savepoint sp = Database.setSavepoint();
String externalId = 'IM-811-TEST-' + DateTime.now().getTime();
try {
    Auctifera__Fund_Donation_Assignment__c fda = new Auctifera__Fund_Donation_Assignment__c(
        Auctifera__Donated_Amount__c = -64,
        Auctifera__Status__c = 'Refunded',
        Auctifera__Accounting_Status__c = 'Posted',
        Auctifera__Specific_Fund__c = 'a35WI000000kj98YAA',
        Auctifera__Posted_Date__c = Date.newInstance(2017, 6, 22),
        vnfp__Opportunity__c = '006WI00000MCRPZYA5',
        Auctifera__LookUp_ID_Legacy__c = null,
        vnfp__Acknowledgment_Status__c = 'Acknowledged',
        Auctifera__Implementation_External_ID__c = externalId
    );
    insert fda;
    System.debug('IM-811 INSERT_OK Id=' + fda.Id);

    Auctifera__Fund_Donation_Assignment__c rb = [
        SELECT Id, Auctifera__Donated_Amount__c, Auctifera__Status__c,
               Auctifera__Accounting_Status__c, Auctifera__Specific_Fund__c,
               Auctifera__Posted_Date__c, vnfp__Opportunity__c,
               vnfp__Opportunity_POS_Purchase__c, Auctifera__LookUp_ID_Legacy__c,
               vnfp__Acknowledgment_Status__c, Auctifera__Implementation_External_ID__c
        FROM Auctifera__Fund_Donation_Assignment__c
        WHERE Id = :fda.Id
    ];
    System.debug('IM-811 READBACK_Donated_Amount=' + rb.Auctifera__Donated_Amount__c);
    System.debug('IM-811 READBACK_Status=' + rb.Auctifera__Status__c);
    System.debug('IM-811 READBACK_Accounting_Status=' + rb.Auctifera__Accounting_Status__c);
    System.debug('IM-811 READBACK_Specific_Fund=' + rb.Auctifera__Specific_Fund__c);
    System.debug('IM-811 READBACK_Posted_Date=' + rb.Auctifera__Posted_Date__c);
    System.debug('IM-811 READBACK_Opportunity=' + rb.vnfp__Opportunity__c);
    System.debug('IM-811 READBACK_POS_Purchase=' + rb.vnfp__Opportunity_POS_Purchase__c);
    System.debug('IM-811 READBACK_LookUp_ID_Legacy=' + rb.Auctifera__LookUp_ID_Legacy__c);
    System.debug('IM-811 READBACK_Acknowledgment_Status=' + rb.vnfp__Acknowledgment_Status__c);
    System.debug('IM-811 READBACK_External_ID=' + rb.Auctifera__Implementation_External_ID__c);
} catch (Exception e) {
    System.debug('IM-811 ERROR ' + e.getTypeName() + ': ' + e.getMessage());
} finally {
    Database.rollback(sp);
    System.debug('IM-811 ROLLBACK_DONE');
}

Integer remaining = [SELECT COUNT() FROM Auctifera__Fund_Donation_Assignment__c WHERE Auctifera__Implementation_External_ID__c = :externalId];
System.debug('IM-811 RESIDUE_CHECK remaining=' + remaining);
