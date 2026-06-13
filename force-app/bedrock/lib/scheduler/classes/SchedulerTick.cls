public with sharing class SchedulerTick implements Schedulable {
    public void execute(SchedulableContext context) {
        Scheduler.tick();
    }
}
