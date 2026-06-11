public with sharing class HelloWorldAsync extends Async {
    
    public override void execute(Set<Id> ids) {
        System.debug('Hello World from Async! Work Item Ids: ' + String.join(new List<Id>(this.workItemIds), ','));
        System.debug('Hello World from Async! Record Ids: ' + String.join(new List<Id>(ids), ','));
        System.debug([SELECT LastName FROM Contact WHERE Id IN :ids]);
        //Integer i = 1/0;
    }

}