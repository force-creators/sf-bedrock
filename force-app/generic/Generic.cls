public virtual with sharing class Generic {
    protected Map<String, Object> generic;
    
    public Generic() {
        this.generic = new Map<String, Object>();
    }

    public Generic(String unknown) {
        this.generic = (Map<String, Object>) JSON.deserializeUntyped(unknown);
    }

    public Generic(Map<String, Object> unknown) {
        this.generic = new Map<String, Object>();
        for(String key : unknown.keySet()) {
            this.generic.put(key, unknown.get(key));
        }
    }

    public Object get(String path) {
        return this.get(path, null);
    }

    public Object get(String path, Type target) {
        Object value = this.get(this.generic, this.normalizeParths(path), 0);
        if (target == null) return value;
        return coerce(value, target);
    }

    public Object get(Object current, List<String> parts, Integer index) {
        Boolean isLast = (index == parts.size() - 1);
        String part = parts.get(index);
        if (current instanceof Map<String, Object>) {
            Map<String, Object> currentMap = (Map<String, Object>) current;
            if(isLast) return currentMap.get(part);
            if(!currentMap.containsKey(part)) return null;
            return get(currentMap.get(part), parts, index + 1);
        }
        if(current instanceof List<Object>) {
            Integer idx = Integer.valueOf(part);
            if(idx == null) return null;
            List<Object> currentList = (List<Object>) current;
            if(idx >= currentList.size()) return null;
            if(isLast) return currentList.get(idx);
            return get(currentList.get(idx), parts, index + 1);
        }
        return null;
    }

    public void put(Map<String, Object> paths) {
        for(String path : paths.keySet()) {
            this.put(path, paths.get(path));
        }
    }

    public void put(String key, Object value) {
        put(this.generic, this.normalizeParths(key), 0, value);
    }

    public void put(Object current, List<String> parts, Integer index, Object value) {
        Boolean isLast = (index == parts.size() - 1);
        String part = parts.get(index);
        if (current instanceof Map<String, Object>) {
            Map<String, Object> currentMap = (Map<String, Object>) current;
            if(isLast) {
                currentMap.put(part, value);
                return;
            }
            if(!currentMap.containsKey(part) || currentMap.get(part) == null) {
                currentMap.put(part, new Map<String, Object>());
            }
            put(currentMap.get(part), parts, index + 1, value);
        }
    }

    public String json() {
        return JSON.serialize(this.generic);
    }

    public SObject sObject(Type target) {
        return (SObject) JSON.deserialize(json(), target);
    }

    public Map<String, Object> generic() {
        return this.generic;
    }

    public virtual Map<String, Object> mapping() {
        return new Map<String, Object>();
    }

    public virtual Map<String, Object> transform() {
        return new Generic(this.mapping()).generic();
    }

    Object coerce(Object value, Type target) {
        if(value == null) return null;
        if(target == null ||
            target == Object.class) return value;

        if(target == String.class) return String.valueOf(value);
        if(target == Integer.class) return Integer.valueOf(String.valueOf(value));
        if(target == Decimal.class) return Decimal.valueOf(String.valueOf(value));
        if(target == Boolean.class) return Boolean.valueOf(String.valueOf(value));
        if(target == Date.class) return Date.valueOf(String.valueOf(value));
        if(target == Datetime.class) return Datetime.valueOf(String.valueOf(value));
        if(target == List<Object>.class) return (List<Object>) value;
        if(target == Map<String, Object>.class) return (Map<String, Object>) value;
        if(target == List<Map<String, Object>>.class) {
            List<Object> currentList = (List<Object>) value;
            List<Map<String, Object>> result = new List<Map<String, Object>>();
            for(Object item : currentList) {
                result.add((Map<String, Object>) item);
            }
            return result;
        }
        return JSON.deserialize(JSON.serialize(value), target);
    }

    List<String> normalizeParths(String path) {
        String normalized = path.replace('[', '.').replace(']', '');
        return normalized.split('\\.');
    }
}