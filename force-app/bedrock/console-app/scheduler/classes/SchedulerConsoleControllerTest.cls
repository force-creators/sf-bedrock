/*
 * sf-bedrock: https://sfbedrock.com
 * Copyright 2026 Matthew Swing-McKenzie and Force Creators
 * SPDX-License-Identifier: MPL-2.0
 * License: https://mozilla.org/MPL/2.0/
 */

@istest(testFor='ApexClass:SchedulerConsoleController')
public with sharing class SchedulerConsoleControllerTest {
  @istest
  static void testGetSchedule_calculatesLiveTimeline() {
    Datetime lastRan = System.now().addHours(-2);
    Datetime nextRun = System.now().addHours(1);
    SchedulerMock mock = new SchedulerMock()
      .config(
        new Scheduler_Job__mdt(
          DeveloperName = 'HourlyJob',
          MasterLabel = 'Hourly Job',
          Apex__c = 'HourlyJob',
          Enabled__c = true,
          Frequency__c = Scheduler.HOURS,
          Interval__c = '3'
        )
      )
      .seedCurrentHash()
      .job(
        new Scheduler__c(
          Apex__c = 'HourlyJob',
          Enabled__c = true,
          Frequency__c = Scheduler.HOURS,
          Interval__c = 3,
          Next_Run__c = nextRun,
          Last_Executed__c = lastRan
        )
      )
      .job(
        new Scheduler__c(
          Apex__c = 'DisabledJob',
          Enabled__c = false,
          Frequency__c = Scheduler.MINUTES,
          Interval__c = 2,
          Error_Message__c = 'Previous failure'
        )
      );
    Scheduler.setMock(mock);
    SchedulerConsoleController.setQueryService(
      new QueryServiceMock(mock.queries.jobs, mock.metadata.configs)
    );

    Test.startTest();
    SchedulerConsoleController.ConsoleState state = SchedulerConsoleController.getSchedule();
    Test.stopTest();

    Scheduler.reset();
    SchedulerConsoleController.reset();

    Assert.areEqual(
      2,
      state.jobs.size(),
      'The console should return one row for each scheduler runtime record.'
    );
    Assert.areEqual(
      1,
      state.enabledJobCount,
      'The console should count enabled scheduler jobs.'
    );
    Assert.areEqual(
      1,
      state.disabledJobCount,
      'The console should count disabled scheduler jobs.'
    );
    Assert.areEqual(
      1,
      state.errorJobCount,
      'The console should count scheduler jobs with a stored last error.'
    );
    Assert.areEqual(
      1,
      state.jobConfigurations.size(),
      'The console should return Scheduler custom metadata configuration rows.'
    );

    SchedulerConsoleController.JobRow hourlyRow = findRow(
      state.jobs,
      'HourlyJob'
    );
    Assert.areEqual(
      nextRun,
      hourlyRow.nextScheduledAt,
      'The console should use the persisted next run time when Scheduler has calculated one.'
    );
    Assert.areEqual(
      'Every 3 hours',
      hourlyRow.cadence,
      'The console should render a readable cadence label for hour-based jobs.'
    );
    Assert.areEqual(
      'Scheduled',
      hourlyRow.status,
      'A future enabled job should be shown as scheduled.'
    );
    Assert.areEqual(
      'Hourly Job',
      state.jobConfigurations[0].label,
      'The console should include the metadata label for the Jobs tab.'
    );
    Assert.areEqual(
      'Every 3 hours',
      state.jobConfigurations[0].cadence,
      'The console should render readable cadence labels for configuration rows.'
    );

    SchedulerConsoleController.JobRow disabledRow = findRow(
      state.jobs,
      'DisabledJob'
    );
    Assert.areEqual(
      null,
      disabledRow.nextScheduledAt,
      'Disabled jobs should not show a next scheduled run time.'
    );
    Assert.areEqual(
      'Every 5 minutes',
      disabledRow.cadence,
      'Minute-based jobs should use the same five-minute minimum as Scheduler.'
    );
    Assert.areEqual(
      'Disabled',
      disabledRow.status,
      'Disabled jobs should be clearly marked as disabled.'
    );
  }

  @istest
  static void testGetSchedule_surfacesPendingMetadataRecalculation() {
    SchedulerMock mock = new SchedulerMock()
      .config(
        new Scheduler_Job__mdt(
          DeveloperName = 'ChangedJob',
          MasterLabel = 'Changed Job',
          Apex__c = 'ChangedJob',
          Enabled__c = true,
          Frequency__c = Scheduler.MINUTES,
          Interval__c = '5'
        )
      )
      .job(
        new Scheduler__c(
          Apex__c = 'ChangedJob',
          Enabled__c = true,
          Frequency__c = Scheduler.MINUTES,
          Interval__c = 5,
          Hash__c = 'stale'
        )
      );
    Scheduler.setMock(mock);
    SchedulerConsoleController.setQueryService(
      new QueryServiceMock(mock.queries.jobs, mock.metadata.configs)
    );

    Test.startTest();
    SchedulerConsoleController.ConsoleState state = SchedulerConsoleController.getSchedule();
    Test.stopTest();

    Scheduler.reset();
    SchedulerConsoleController.reset();

    Assert.isTrue(
      state.hasMetadataChanges,
      'The console should detect when runtime scheduler rows no longer match metadata.'
    );
    Assert.isNotNull(
      state.metadataRecalculationAt,
      'The console should report the next heartbeat time when metadata will be recalculated.'
    );
    Assert.isTrue(
      state.metadataRecalculationAt >= state.generatedAt,
      'The recalculation time should not be earlier than the console snapshot time.'
    );
  }

  @istest
  static void testGetSchedule_calculatesWeeklyAndMonthlyFallbackCadence() {
    Datetime lastWeekRun = System.now().addDays(-7);
    Datetime lastMonthRun = System.now().addMonths(-1);
    SchedulerMock mock = new SchedulerMock()
      .seedCurrentHash()
      .job(
        new Scheduler__c(
          Apex__c = 'WeeklyJob',
          Enabled__c = true,
          Frequency__c = Scheduler.WEEKS,
          Interval__c = 2,
          Last_Executed__c = lastWeekRun
        )
      )
      .job(
        new Scheduler__c(
          Apex__c = 'MonthlyJob',
          Enabled__c = true,
          Frequency__c = Scheduler.MONTHS,
          Interval__c = 2,
          Last_Executed__c = lastMonthRun
        )
      );
    Scheduler.setMock(mock);
    SchedulerConsoleController.setQueryService(
      new QueryServiceMock(mock.queries.jobs)
    );

    Test.startTest();
    SchedulerConsoleController.ConsoleState state = SchedulerConsoleController.getSchedule();
    Test.stopTest();

    Scheduler.reset();
    SchedulerConsoleController.reset();

    SchedulerConsoleController.JobRow weeklyRow = findRow(
      state.jobs,
      'WeeklyJob'
    );
    Assert.areEqual(
      lastWeekRun.addDays(14),
      weeklyRow.nextScheduledAt,
      'The console should project weekly jobs from the last executed time when no next run is stored yet.'
    );
    Assert.areEqual(
      'Every 2 weeks',
      weeklyRow.cadence,
      'The console should render a readable cadence label for weekly jobs.'
    );

    SchedulerConsoleController.JobRow monthlyRow = findRow(
      state.jobs,
      'MonthlyJob'
    );
    Assert.areEqual(
      lastMonthRun.addMonths(2),
      monthlyRow.nextScheduledAt,
      'The console should project monthly jobs from the last executed time when no next run is stored yet.'
    );
    Assert.areEqual(
      'Every 2 months',
      monthlyRow.cadence,
      'The console should render a readable cadence label for monthly jobs.'
    );
  }

  static SchedulerConsoleController.JobRow findRow(
    List<SchedulerConsoleController.JobRow> rows,
    String apexClass
  ) {
    for (SchedulerConsoleController.JobRow row : rows) {
      if (row.apexClass == apexClass)
        return row;
    }

    Assert.fail('Expected to find scheduler row for ' + apexClass + '.');
    return null;
  }

  class QueryServiceMock extends SchedulerConsoleController.QueryService {
    List<Scheduler__c> jobs;
    List<Scheduler_Job__mdt> configs;

    QueryServiceMock(List<Scheduler__c> jobs) {
      this(jobs, new List<Scheduler_Job__mdt>());
    }

    QueryServiceMock(
      List<Scheduler__c> jobs,
      List<Scheduler_Job__mdt> configs
    ) {
      this.jobs = jobs;
      this.configs = configs;
    }

    public override List<Scheduler__c> getJobs() {
      return jobs;
    }

    public override List<Scheduler_Job__mdt> getJobConfigurations() {
      return configs;
    }
  }
}
