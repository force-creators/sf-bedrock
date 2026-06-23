/*
 * sf-bedrock: https://sfbedrock.com
 * Copyright 2026 Matthew Swing-McKenzie and Force Creators
 * SPDX-License-Identifier: MPL-2.0
 * License: https://mozilla.org/MPL/2.0/
 */

public with sharing class SchedulerTick implements Schedulable {
  public void execute(SchedulableContext context) {
    Scheduler.tick();
  }
}
