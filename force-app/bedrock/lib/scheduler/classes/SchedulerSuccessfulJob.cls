@istest
public with sharing class SchedulerSuccessfulJob extends Scheduler {
    public static Integer executions = 0;

    public override void execute() {
        executions++;
    }
}
