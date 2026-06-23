/*
 * sf-bedrock: https://sfbedrock.com
 * Copyright 2026 Matthew Swing-McKenzie and Force Creators
 * SPDX-License-Identifier: MPL-2.0
 * License: https://mozilla.org/MPL/2.0/
 */

public with sharing class AsyncThread implements Queueable {
    public Id threadId;
    public Integer failures;
    public String runKey;

    public AsyncThread(Id threadId, Integer failures) {
        this(threadId, failures, Thread.service.currentRunKey(threadId));
    }

    public AsyncThread(Id threadId, Integer failures, String runKey) {
        this.threadId = threadId;
        this.failures = failures == null ? 0 : failures;
        this.runKey = runKey;
    }

    public void execute(QueueableContext context) {
        new ThreadRunner(this.threadId, this.failures, this.runKey)
            .execute(context);
    }
}
