/**
 * Controller for the public DemoConfig page. Kept without sharing so the Site's
 * guest user can read the demo records through it; the page is read-only and
 * only ever returns configuration meant to be public.
 */
public without sharing class DemoConfigController {

    public String getConfigJson() {
        Map<String, String> params = ApexPages.currentPage().getParameters();
        String demoKey = params.get('id');
        try {
            if (params.containsKey('list')) {
                return DemoConfigService.buildListJson();
            }
            return DemoConfigService.buildJson(demoKey);
        } catch (Exception e) {
            return JSON.serialize(new Map<String, Object>{
                'error' => e.getMessage()
            });
        }
    }
}
