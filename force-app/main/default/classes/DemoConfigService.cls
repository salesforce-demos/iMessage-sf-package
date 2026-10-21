/**
 * Builds the JSON that iOS-NativeiMessage consumes, straight from the
 * iMessage_Demo__c records. The shape has to match the app's AppConfig decoder
 * exactly — see Configs.json in the app for the reference document.
 *
 * The conversations are read once and feed two blocks of that payload: the
 * Messages threads, and the `contacts` the Phone app lists in Favorites. One
 * record behind both is what keeps a contact's name, avatar and conversation
 * from ever drifting apart.
 *
 * Banners hang off the call they belong to, so every contact can drop its own
 * sequence in at its own pace. A banner with no call named stays in the
 * demo-wide `callNotifications`, which is the shape older configs use.
 */
public with sharing class DemoConfigService {

    public class ConfigNotFoundException extends Exception {}

    /**
     * Demos ticked Show In App, as name + key pairs, so the app's setup screen
     * can offer them as a list instead of asking for a pasted URL.
     */
    public static String buildListJson() {
        List<Object> demos = new List<Object>();
        for (iMessage_Demo__c d : [
            SELECT Name, Config_Name__c
            FROM iMessage_Demo__c
            WHERE Show_In_App__c = TRUE AND Config_Name__c != NULL
            ORDER BY Name
        ]) {
            demos.add(new Map<String, Object>{ 'name' => d.Name, 'id' => d.Config_Name__c });
        }
        return JSON.serialize(new Map<String, Object>{ 'demos' => demos });
    }

    /**
     * @param demoKey  Config_Name__c of the demo to serve. Blank falls back to
     *                 the record flagged Is_Active__c.
     */
    /** A banner with no call of its own belongs to the demo-wide list. */
    private static final String SHARED_CALL = '';

    public static String buildJson(String demoKey) {
        iMessage_Demo__c demo = findDemo(demoKey);

        List<iMessage_Conversation__c> convs = conversationRecords(demo.Id);
        Map<String, List<Object>> banners = notificationsByCall(demo.Id);

        Map<String, Object> root = stripNulls(new Map<String, Object>{
            'configName' => demo.Config_Name__c,
            'statusBar'  => new Map<String, Object>{ 'chatview' => statusBar(demo) },
            'callNotifications' => banners.get(SHARED_CALL),
            'conversations'     => conversations(demo, convs),
            'contacts'          => contacts(convs, banners)
        });

        // suppressApexObjectNulls keeps optional keys out of the payload, which
        // the Swift side treats the same as absent.
        return JSON.serialize(root, true);
    }

    private static iMessage_Demo__c findDemo(String demoKey) {
        List<iMessage_Demo__c> found;
        if (String.isNotBlank(demoKey)) {
            found = [
                SELECT Id, Config_Name__c, Bubble_Style__c,
                       SB_Carrier__c, SB_Signal_Bars__c, SB_WiFi_Strength__c,
                       SB_Show_WiFi__c, SB_Battery_Level__c, SB_Is_Charging__c
                FROM iMessage_Demo__c
                WHERE Config_Name__c = :demoKey
                LIMIT 1
            ];
        } else {
            found = [
                SELECT Id, Config_Name__c, Bubble_Style__c,
                       SB_Carrier__c, SB_Signal_Bars__c, SB_WiFi_Strength__c,
                       SB_Show_WiFi__c, SB_Battery_Level__c, SB_Is_Charging__c
                FROM iMessage_Demo__c
                WHERE Is_Active__c = TRUE
                ORDER BY LastModifiedDate DESC
                LIMIT 1
            ];
        }
        if (found.isEmpty()) {
            throw new ConfigNotFoundException(
                String.isNotBlank(demoKey)
                    ? 'No iMessage Demo named "' + demoKey + '".'
                    : 'No iMessage Demo is marked Is Active.'
            );
        }
        return found[0];
    }

    private static Map<String, Object> statusBar(iMessage_Demo__c d) {
        return stripNulls(new Map<String, Object>{
            'carrier'      => d.SB_Carrier__c,
            'signalBars'   => intOrNull(d.SB_Signal_Bars__c),
            'wifiStrength' => intOrNull(d.SB_WiFi_Strength__c),
            'showWifi'     => d.SB_Show_WiFi__c,
            'levelBattery' => d.SB_Battery_Level__c,
            'isCharging'   => d.SB_Is_Charging__c
        });
    }

    /**
     * The banners of the demo, grouped by the call they drop into. The key is
     * the Conversation Key of the contact being called; everything without a
     * call of its own lands under SHARED_CALL, which is the demo-wide list the
     * app falls back to for configs written before per-call banners.
     *
     * Sort_Order__c is the running order on purpose: a banner with no
     * `afterSeconds` of its own follows nine seconds behind the one before it,
     * so the author's order is the schedule.
     */
    private static Map<String, List<Object>> notificationsByCall(Id demoId) {
        Map<String, List<Object>> byCall = new Map<String, List<Object>>();

        for (iMessage_Notification__c n : [
            SELECT Icon_Name__c, Icon_Color__c, Document_Icon__c,
                   Title__c, Message__c, Time_Ago__c, Conversation_Key__c,
                   Call_Key__c, After_Seconds__c
            FROM iMessage_Notification__c
            WHERE Demo__c = :demoId
            ORDER BY Sort_Order__c NULLS LAST, Name
        ]) {
            String call = n.Call_Key__c == null ? SHARED_CALL : n.Call_Key__c;
            if (!byCall.containsKey(call)) { byCall.put(call, new List<Object>()); }

            byCall.get(call).add(stripNulls(new Map<String, Object>{
                'iconName'       => n.Icon_Name__c,
                'iconColor'      => n.Icon_Color__c,
                'documentIcon'   => n.Document_Icon__c,
                'title'          => n.Title__c,
                'message'        => n.Message__c,
                'timeAgo'        => n.Time_Ago__c,
                'conversationId' => n.Conversation_Key__c,
                'afterSeconds'   => n.After_Seconds__c
            }));
        }
        return byCall;
    }

    /**
     * Demo-wide override for the bubble colour. Null means the demo does not
     * force anything and each conversation keeps its own Is_SMS__c.
     */
    private static Boolean forcedIsSMS(iMessage_Demo__c d) {
        if (d.Bubble_Style__c == 'SMS')      { return true;  }
        if (d.Bubble_Style__c == 'iMessage') { return false; }
        return null;
    }

    /**
     * Read once: the conversations feed both the Messages threads and the
     * Phone contacts, and the two have to agree on order and content.
     */
    private static List<iMessage_Conversation__c> conversationRecords(Id demoId) {
        return [
            SELECT Id, Conversation_Key__c, Contact_Name__c, Contact_Subtitle__c, Avatar_URL__c,
                   Last_Message_Preview__c, Last_Message_Time__c, Unread_Count__c,
                   Is_SMS__c, Is_Muted__c, Is_Forwarded__c, Transcript_Speed__c, Draft_Text__c,
                   Show_In_Phone__c, Phone_Label__c, Phone_Sort_Order__c, Call_Subtitle__c,
                   Call_Background_URL__c, Ring_Seconds__c, Notification_After_Seconds__c,
                   Agent_Connection__c, Agent_My_Domain__c, Agent_Id__c, Agent_ES_Developer_Name__c,
                   Agent_Org_Id__c, Agent_SCRT_URL__c, Agent_Greeting__c
            FROM iMessage_Conversation__c
            WHERE Demo__c = :demoId
            ORDER BY Sort_Order__c NULLS LAST, Name
        ];
    }

    /**
     * Favorites is its own running order: the contact you call first is rarely
     * the thread at the top of Messages. Phone_Sort_Order__c carries it, and a
     * blank one keeps the conversation's own position, behind everyone who
     * asked for a place.
     */
    private static List<iMessage_Conversation__c> inPhoneOrder(List<iMessage_Conversation__c> convs) {
        List<ContactOrder> ranked = new List<ContactOrder>();
        Integer position = 0;
        for (iMessage_Conversation__c c : convs) {
            position++;
            if (c.Show_In_Phone__c == true) { ranked.add(new ContactOrder(c, position)); }
        }
        ranked.sort();

        List<iMessage_Conversation__c> out = new List<iMessage_Conversation__c>();
        for (ContactOrder r : ranked) { out.add(r.row); }
        return out;
    }

    private class ContactOrder implements Comparable {
        final iMessage_Conversation__c row;
        final Decimal rank;
        /** Ties and blanks both fall back to the Messages order, so it is stable. */
        final Integer fallback;

        ContactOrder(iMessage_Conversation__c row, Integer fallback) {
            this.row = row;
            this.fallback = fallback;
            this.rank = row.Phone_Sort_Order__c;
        }

        public Integer compareTo(Object other) {
            ContactOrder o = (ContactOrder) other;
            if (rank != o.rank) {
                if (rank == null)   { return 1;  }
                if (o.rank == null) { return -1; }
                return rank < o.rank ? -1 : 1;
            }
            if (fallback == o.fallback) { return 0; }
            return fallback < o.fallback ? -1 : 1;
        }
    }

    /**
     * The Phone app's Favorites, Recents and Contacts tabs. Every entry is one
     * of the conversations above, so the name and avatar can never drift and
     * `conversationId` always points at a thread that exists. `id` is the
     * position in this list, which is what the app keys its avatar cache on —
     * nobody has to invent or maintain a number.
     */
    private static List<Object> contacts(
        List<iMessage_Conversation__c> convs,
        Map<String, List<Object>> banners
    ) {
        List<Object> out = new List<Object>();
        Integer contactId = 0;
        for (iMessage_Conversation__c c : inPhoneOrder(convs)) {
            String phoneLabel = String.isBlank(c.Phone_Label__c) ? 'mobile' : c.Phone_Label__c;
            out.add(stripNulls(new Map<String, Object>{
                'id'                       => ++contactId,
                'name'                     => c.Contact_Name__c,
                'phoneLabel'               => phoneLabel,
                'avatar'                   => c.Avatar_URL__c,
                'backgroundURL'            => c.Call_Background_URL__c,
                // Blank is not a gap to fill here: the app writes
                // "calling <label>…" itself, and it stays in sync with the label.
                'subtitle'                 => c.Call_Subtitle__c,
                'ringSeconds'              => c.Ring_Seconds__c,
                'notificationAfterSeconds' => c.Notification_After_Seconds__c,
                'conversationId'           => c.Conversation_Key__c,
                // Absent when this call has no banners of its own, and then the
                // app falls back to the shared list.
                'notifications'            => banners.get(c.Conversation_Key__c),
                'voice'                    => voice(c)
            }));
        }
        return out;
    }

    /**
     * The live voice line that answers this contact's calls in
     * iOS-NativePhoneAgent. A My Domain is what turns it on: without one the
     * key stays out and the call is the fake one. The plain iOS-NativeiMessage
     * app never reads it.
     */
    private static Map<String, Object> voice(iMessage_Conversation__c c) {
        if (String.isBlank(c.Agent_My_Domain__c)) { return null; }
        return stripNulls(new Map<String, Object>{
            'connection'      => blankToNull(c.Agent_Connection__c),
            'myDomain'        => c.Agent_My_Domain__c.trim(),
            'agentId'         => blankToNull(c.Agent_Id__c),
            'esDeveloperName' => blankToNull(c.Agent_ES_Developer_Name__c),
            'organizationId'  => blankToNull(c.Agent_Org_Id__c),
            'serviceApiURL'   => blankToNull(c.Agent_SCRT_URL__c),
            'greeting'        => blankToNull(c.Agent_Greeting__c)
        });
    }

    private static List<Object> conversations(iMessage_Demo__c demo, List<iMessage_Conversation__c> convs) {
        Boolean forced = forcedIsSMS(demo);

        Map<Id, List<Object>> byConv = messagesByConversation(new Map<Id, iMessage_Conversation__c>(convs).keySet());

        List<Object> out = new List<Object>();
        for (iMessage_Conversation__c c : convs) {
            Map<String, Object> row = stripNulls(new Map<String, Object>{
                'id'                 => c.Conversation_Key__c,
                'contactName'        => c.Contact_Name__c,
                'contactSubtitle'    => c.Contact_Subtitle__c,
                'avatarURL'          => c.Avatar_URL__c,
                'lastMessagePreview' => c.Last_Message_Preview__c,
                'lastMessageTime'    => c.Last_Message_Time__c,
                'unreadCount'        => intOrNull(c.Unread_Count__c),
                'isSMS'              => forced == null ? c.Is_SMS__c : forced,
                'isMuted'            => c.Is_Muted__c,
                'isForwarded'        => c.Is_Forwarded__c,
                'transcriptSpeed'    => intOrNull(c.Transcript_Speed__c),
                'draftText'          => c.Draft_Text__c
            });
            row.put('messages', byConv.containsKey(c.Id) ? byConv.get(c.Id) : new List<Object>());
            out.add(row);
        }
        return out;
    }

    private static Map<Id, List<Object>> messagesByConversation(Set<Id> convIds) {
        Map<Id, List<Object>> byConv = new Map<Id, List<Object>>();
        for (iMessage_Message__c m : [
            SELECT Conversation__c, Sender__c, Text__c, Image_URL__c, Send_Automatically__c,
                   Typing_Seconds__c, Pause_Seconds__c, Delivery_Status__c, Tapback__c,
                   Effect__c, Await_Photo__c, React_To_Previous__c, Reply_To_Step__c
            FROM iMessage_Message__c
            WHERE Conversation__c IN :convIds
            ORDER BY Sort_Order__c NULLS LAST, Name
        ]) {
            if (!byConv.containsKey(m.Conversation__c)) {
                byConv.put(m.Conversation__c, new List<Object>());
            }
            byConv.get(m.Conversation__c).add(stripNulls(new Map<String, Object>{
                'sender'            => m.Sender__c,
                'text'              => m.Text__c,
                'imageURL'          => m.Image_URL__c,
                'sendAutomatically' => m.Send_Automatically__c,
                'typingSeconds'     => m.Typing_Seconds__c,
                'pauseSeconds'      => m.Pause_Seconds__c,
                'deliveryStatus'    => m.Delivery_Status__c,
                'tapback'           => m.Tapback__c,
                'effect'            => m.Effect__c,
                'awaitPhoto'        => m.Await_Photo__c,
                'reactToPrevious'   => m.React_To_Previous__c,
                'replyTo'           => intOrNull(m.Reply_To_Step__c)
            }));
        }
        return byConv;
    }

    // MARK: helpers

    /** JSON.serialize's null suppression does not reach into nested maps. */
    private static Map<String, Object> stripNulls(Map<String, Object> m) {
        Map<String, Object> out = new Map<String, Object>();
        for (String k : m.keySet()) {
            if (m.get(k) != null) { out.put(k, m.get(k)); }
        }
        return out;
    }

    private static String blankToNull(String v) {
        return String.isBlank(v) ? null : v.trim();
    }

    private static Integer intOrNull(Decimal d) {
        return d == null ? null : Integer.valueOf(d);
    }
}