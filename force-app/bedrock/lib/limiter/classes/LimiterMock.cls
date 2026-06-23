/*
 * sf-bedrock: https://sfbedrock.com
 * Copyright 2026 Matthew Swing-McKenzie and Force Creators
 * SPDX-License-Identifier: MPL-2.0
 * License: https://mozilla.org/MPL/2.0/
 */

public inherited sharing class LimiterMock extends Limiter.Service {
    public Map<String, Limiter.LimitUsage> currentLimits = new Map<String, Limiter.LimitUsage>();

    public LimiterMock setLimit(String name, Integer used, Integer allowed) {
        Limiter.LimitUsage limitUsage = new Limiter.LimitUsage(
            name,
            used,
            allowed
        );
        this.currentLimits.put(limitUsage.name, limitUsage);
        return this;
    }

    public LimiterMock setLimit(
        Limiter.types name,
        Integer used,
        Integer allowed
    ) {
        return this.setLimit(Limiter.key(name), used, allowed);
    }

    public LimiterMock limits(Map<String, Limiter.LimitUsage> currentLimits) {
        this.currentLimits = currentLimits == null
            ? new Map<String, Limiter.LimitUsage>()
            : currentLimits;
        return this;
    }

    public override Map<String, Limiter.LimitUsage> getLimits() {
        return this.currentLimits;
    }
}
