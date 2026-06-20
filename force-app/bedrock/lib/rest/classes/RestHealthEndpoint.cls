public inherited sharing class RestHealthEndpoint extends Rest {
    public override void get(Rest.Request request) {
        respond(new Map<String, Object> {
            'status' => 'ok',
            'route' => request.route,
            'version' => request.version,
            'primaryContext' => request.primaryContext,
            'secondaryContext' => request.secondaryContext
        });
    }
}
