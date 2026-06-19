public virtual with sharing class EventRelayHandlerService {
    public virtual EventRelay.Handler forWorkItems(List<Event__c> workItems) {
        if (workItems == null || workItems.isEmpty()) return new EventRelay.Handler();

        String handlerClass = workItems[0].Apex__c;
        for (Event__c workItem : workItems) {
            if (workItem.Apex__c != handlerClass) {
                throw new EventRelay.EventRelayException('A process batch can only contain one handler class.');
            }
        }
        return forClass(handlerClass);
    }

    public virtual EventRelay.Handler forClass(String handlerClass) {
        if (String.isBlank(handlerClass)) {
            throw new EventRelay.EventRelayException('EventRelay process work requires a handler class.');
        }

        String safeHandlerClass = handlerClass.trim();
        Type handlerType = Type.forName(safeHandlerClass);
        if (handlerType == null) {
            throw new EventRelay.EventRelayException('Unknown EventRelay handler class ' + safeHandlerClass + '.');
        }

        Object handlerInstance = handlerType.newInstance();
        if (!(handlerInstance instanceof EventRelay.Handler)) {
            throw new EventRelay.EventRelayException(safeHandlerClass + ' must extend EventRelay.Handler.');
        }
        return (EventRelay.Handler) handlerInstance;
    }
}
