public with sharing class HelloWorldJob extends Scheduler {
    public override void execute() {
        System.debug('Hello, World! The time is: ' + System.now());
    }
}