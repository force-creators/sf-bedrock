trigger EventRelayWakeTrigger on EventRelay_Wake__e(after insert) {
    EventRelay.wake();
}
