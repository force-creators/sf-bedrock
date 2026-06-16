public with sharing class ThreadRecoveryJob extends Scheduler {
    public override void execute() {
        Thread.recover();
    }
}
