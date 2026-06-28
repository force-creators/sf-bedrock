public without sharing class TormentPingPongQueueable implements Queueable {
    List<String> messages;

    public TormentPingPongQueueable(List<String> messages) {
        this.messages = messages == null ? new List<String>() : messages;
    }

    public void execute(QueueableContext context) {
        List<Bedrock_Test_Event__e> nextEvents = new List<Bedrock_Test_Event__e>();
        for (String message : messages) {
            Map<String, String> parts = parse(message);
            Integer hop = intValue(parts, 'hop', 0);
            Integer maxHop = intValue(parts, 'max', 1);
            Integer fan = Math.max(1, Math.min(3, intValue(parts, 'fan', 1)));
            if (hop >= maxHop) {
                continue;
            }

            for (Integer index = 0; index < fan; index++) {
                nextEvents.add(
                    new Bedrock_Test_Event__e(
                        Message__c = nextMessage(
                            parts,
                            hop + 1,
                            maxHop,
                            fan,
                            index
                        )
                    )
                );
                if (nextEvents.size() >= 100) {
                    publishAndClear(nextEvents);
                }
            }
        }
        publishAndClear(nextEvents);
    }

    static void publishAndClear(List<Bedrock_Test_Event__e> events) {
        if (events == null || events.isEmpty()) {
            return;
        }
        EventBus.publish(events);
        events.clear();
    }

    static String nextMessage(
        Map<String, String> parts,
        Integer hop,
        Integer maxHop,
        Integer fan,
        Integer fanIndex
    ) {
        String run = parts.containsKey('run') ? parts.get('run') : 'missing';
        String sequence = parts.containsKey('seq')
            ? parts.get('seq')
            : 'missing';
        return 'TORMENT|run=' +
            run +
            '|seq=' +
            sequence +
            '-' +
            String.valueOf(fanIndex) +
            '|hop=' +
            String.valueOf(hop) +
            '|max=' +
            String.valueOf(maxHop) +
            '|fan=' +
            String.valueOf(fan);
    }

    static Map<String, String> parse(String message) {
        Map<String, String> parts = new Map<String, String>();
        if (String.isBlank(message)) {
            return parts;
        }

        for (String token : message.split('\\|')) {
            Integer delimiter = token.indexOf('=');
            if (delimiter < 1) {
                continue;
            }
            parts.put(
                token.substring(0, delimiter),
                token.substring(delimiter + 1)
            );
        }
        return parts;
    }

    static Integer intValue(
        Map<String, String> parts,
        String key,
        Integer fallback
    ) {
        if (parts == null || !parts.containsKey(key)) {
            return fallback;
        }
        try {
            return Integer.valueOf(parts.get(key));
        } catch (Exception error) {
            return fallback;
        }
    }
}
