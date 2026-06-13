@istest
public with sharing class SchedulerFailingJob extends Scheduler {
    public override void execute() {
        throw new Scheduler.SchedulerException('Scheduler job failed.');
    }
}
