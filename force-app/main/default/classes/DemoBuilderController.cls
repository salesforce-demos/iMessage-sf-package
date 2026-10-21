/**
 * Backs the visual builder LWC: loads a whole demo as one tree, saves it back
 * in one call, and hands out the public endpoint URL.
 */
public with sharing class DemoBuilderController {

    // MARK: - Wrappers

    public class DemoTree {
        @AuraEnabled public Demo demo;
        @AuraEnabled public List<Notif> notifications = new List<Notif>();
        @AuraEnabled public List<Conversation> conversations = new List<Conversation>();
        /** Stable URL for this demo: always includes ?id=<Config_Name__c>. */
        @AuraEnabled public String endpointUrl;
        /** Bare Site URL that serves whichever demo is marked as default. */
        @AuraEnabled public String defaultUrl;
        /** Hash of the last loaded tree. Saves with a stale hash are rejected. */
        @AuraEnabled public String versionToken;
    }

    public class Demo {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String configName;
        @AuraEnabled public Boolean isActive;
        @AuraEnabled public Boolean showInApp;
        /** '', 'iMessage' or 'SMS' — blank leaves the colour to each conversation. */
        @AuraEnabled public String bubbleStyle;
        @AuraEnabled public String carrier;
        @AuraEnabled public Decimal signalBars;
        @AuraEnabled public Decimal wifiStrength;
        @AuraEnabled public Boolean showWifi;
        @AuraEnabled public Decimal batteryLevel;
        @AuraEnabled public Boolean isCharging;
    }

    public class Notif {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String iconName;
        @AuraEnabled public String iconColor;
        @AuraEnabled public String documentIcon;
        @AuraEnabled public String title;
        @AuraEnabled public String message;
        @AuraEnabled public String timeAgo;
        /** Conversation Key of the thread the banner opens when tapped. */
        @AuraEnabled public String conversationKey;
        /** Conversation Key of the call it drops into. Blank = the shared list. */
        @AuraEnabled public String callKey;
        /** Seconds after the call connects. Blank follows the previous banner. */
        @AuraEnabled public Decimal afterSeconds;
    }

    public class Conversation {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String conversationKey;
        @AuraEnabled public String contactName;
        @AuraEnabled public String contactSubtitle;
        @AuraEnabled public String avatarUrl;
        @AuraEnabled public String lastMessagePreview;
        @AuraEnabled public String lastMessageTime;
        @AuraEnabled public Decimal unreadCount;
        @AuraEnabled public Boolean isSMS;
        @AuraEnabled public Boolean isMuted;
        @AuraEnabled public Boolean isForwarded;
        @AuraEnabled public Decimal transcriptSpeed;
        @AuraEnabled public String draftText;
        /** Ticked, this thread's contact also appears in the app's Phone tab. */
        @AuraEnabled public Boolean showInPhone;
        @AuraEnabled public String phoneLabel;
        /** Position in Favorites. Renumbered 1..N on save, so it is always dense. */
        @AuraEnabled public Decimal phoneSortOrder;
        @AuraEnabled public String callSubtitle;
        @AuraEnabled public String callBackgroundUrl;
        @AuraEnabled public Decimal ringSeconds;
        @AuraEnabled public Decimal notificationAfterSeconds;
        /** Live voice line for this contact's calls. A blank My Domain means none. */
        @AuraEnabled public String voiceConnection;
        @AuraEnabled public String voiceMyDomain;
        @AuraEnabled public String voiceAgentId;
        @AuraEnabled public String voiceEsDeveloperName;
        @AuraEnabled public String voiceOrgId;
        @AuraEnabled public String voiceScrtUrl;
        @AuraEnabled public String voiceGreeting;
        @AuraEnabled public List<Msg> messages = new List<Msg>();
    }

    public class Msg {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String sender;
        @AuraEnabled public String text;
        @AuraEnabled public String imageUrl;
        @AuraEnabled public Boolean sendAutomatically;
        @AuraEnabled public Decimal typingSeconds;
        @AuraEnabled public Decimal pauseSeconds;
        @AuraEnabled public String deliveryStatus;
        @AuraEnabled public String tapback;
        @AuraEnabled public String effect;
        @AuraEnabled public Boolean awaitPhoto;
        @AuraEnabled public String reactToPrevious;
        /** 1-based position of the step this one replies to; null for a normal message. */
        @AuraEnabled public Decimal replyToStep;
    }

    public class DemoSummary {
        @AuraEnabled public String id;
        @AuraEnabled public String label;
        @AuraEnabled public Boolean isActive;
    }

    // MARK: - Read

    @AuraEnabled(cacheable=true)
    public static List<DemoSummary> listDemos() {
        List<DemoSummary> out = new List<DemoSummary>();
        for (iMessage_Demo__c d : [
            SELECT Id, Name, Config_Name__c, Is_Active__c
            FROM iMessage_Demo__c
            // Same tie-break the endpoint uses, so the picker always opens on
            // the demo that is actually being served.
            ORDER BY Is_Active__c DESC, LastModifiedDate DESC, Name
        ]) {
            DemoSummary s = new DemoSummary();
            s.id = d.Id;
            s.label = d.Name + (d.Is_Active__c ? '  ●' : '');
            s.isActive = d.Is_Active__c;
            out.add(s);
        }
        return out;
    }

    @AuraEnabled
    public static DemoTree loadDemo(String demoId) {
        List<iMessage_Demo__c> found = [
            SELECT Id, Name, Config_Name__c, Is_Active__c, Show_In_App__c, Bubble_Style__c,
                   SB_Carrier__c, SB_Signal_Bars__c, SB_WiFi_Strength__c, SB_Show_WiFi__c,
                   SB_Battery_Level__c, SB_Is_Charging__c
            FROM iMessage_Demo__c WHERE Id = :demoId LIMIT 1
        ];
        // Reseeding the org deletes and reinserts, so an open builder can be
        // holding an Id that no longer exists. Say so instead of blowing up.
        if (found.isEmpty()) {
            throw new AuraHandledException('That demo no longer exists — it was probably replaced.');
        }
        iMessage_Demo__c d = found[0];

        DemoTree t = new DemoTree();
        Demo m = new Demo();
        m.id = d.Id; m.name = d.Name; m.configName = d.Config_Name__c;
        m.isActive = d.Is_Active__c;
        m.showInApp = d.Show_In_App__c;
        m.bubbleStyle = d.Bubble_Style__c;
        m.carrier = d.SB_Carrier__c; m.signalBars = d.SB_Signal_Bars__c;
        m.wifiStrength = d.SB_WiFi_Strength__c; m.showWifi = d.SB_Show_WiFi__c;
        m.batteryLevel = d.SB_Battery_Level__c; m.isCharging = d.SB_Is_Charging__c;
        t.demo = m;

        for (iMessage_Notification__c n : [
            SELECT Id, Name, Icon_Name__c, Icon_Color__c, Document_Icon__c,
                   Title__c, Message__c, Time_Ago__c, Conversation_Key__c,
                   Call_Key__c, After_Seconds__c
            FROM iMessage_Notification__c WHERE Demo__c = :d.Id
            ORDER BY Sort_Order__c NULLS LAST, Name
        ]) {
            Notif w = new Notif();
            w.id = n.Id; w.name = n.Name; w.iconName = n.Icon_Name__c;
            w.iconColor = n.Icon_Color__c; w.documentIcon = n.Document_Icon__c;
            w.title = n.Title__c; w.message = n.Message__c; w.timeAgo = n.Time_Ago__c;
            w.conversationKey = n.Conversation_Key__c;
            w.callKey = n.Call_Key__c; w.afterSeconds = n.After_Seconds__c;
            t.notifications.add(w);
        }

        Map<Id, Conversation> byId = new Map<Id, Conversation>();
        List<Id> order = new List<Id>();
        for (iMessage_Conversation__c c : [
            SELECT Id, Name, Conversation_Key__c, Contact_Name__c, Contact_Subtitle__c, Avatar_URL__c,
                   Last_Message_Preview__c, Last_Message_Time__c, Unread_Count__c,
                   Is_SMS__c, Is_Muted__c, Is_Forwarded__c, Transcript_Speed__c, Draft_Text__c,
                   Show_In_Phone__c, Phone_Label__c, Phone_Sort_Order__c, Call_Subtitle__c,
                   Call_Background_URL__c, Ring_Seconds__c, Notification_After_Seconds__c,
                   Agent_Connection__c, Agent_My_Domain__c, Agent_Id__c, Agent_ES_Developer_Name__c,
                   Agent_Org_Id__c, Agent_SCRT_URL__c, Agent_Greeting__c
            FROM iMessage_Conversation__c WHERE Demo__c = :d.Id
            ORDER BY Sort_Order__c NULLS LAST, Name
        ]) {
            Conversation w = new Conversation();
            w.id = c.Id; w.name = c.Name; w.conversationKey = c.Conversation_Key__c;
            w.contactName = c.Contact_Name__c; w.contactSubtitle = c.Contact_Subtitle__c;
            w.avatarUrl = c.Avatar_URL__c; w.lastMessagePreview = c.Last_Message_Preview__c;
            w.lastMessageTime = c.Last_Message_Time__c; w.unreadCount = c.Unread_Count__c;
            w.isSMS = c.Is_SMS__c; w.isMuted = c.Is_Muted__c; w.isForwarded = c.Is_Forwarded__c;
            w.transcriptSpeed = c.Transcript_Speed__c; w.draftText = c.Draft_Text__c;
            w.showInPhone = c.Show_In_Phone__c; w.phoneLabel = c.Phone_Label__c;
            w.phoneSortOrder = c.Phone_Sort_Order__c;
            w.callSubtitle = c.Call_Subtitle__c; w.callBackgroundUrl = c.Call_Background_URL__c;
            w.ringSeconds = c.Ring_Seconds__c;
            w.notificationAfterSeconds = c.Notification_After_Seconds__c;
            w.voiceConnection = c.Agent_Connection__c; w.voiceMyDomain = c.Agent_My_Domain__c;
            w.voiceAgentId = c.Agent_Id__c; w.voiceEsDeveloperName = c.Agent_ES_Developer_Name__c;
            w.voiceOrgId = c.Agent_Org_Id__c; w.voiceScrtUrl = c.Agent_SCRT_URL__c;
            w.voiceGreeting = c.Agent_Greeting__c;
            byId.put(c.Id, w); order.add(c.Id);
        }
        for (iMessage_Message__c msg : [
            SELECT Id, Conversation__c, Name, Sender__c, Text__c, Image_URL__c, Send_Automatically__c,
                   Typing_Seconds__c, Pause_Seconds__c, Delivery_Status__c, Tapback__c,
                   Effect__c, Await_Photo__c, React_To_Previous__c, Reply_To_Step__c
            FROM iMessage_Message__c WHERE Conversation__c IN :byId.keySet()
            ORDER BY Sort_Order__c NULLS LAST, Name
        ]) {
            Msg w = new Msg();
            w.id = msg.Id; w.name = msg.Name; w.sender = msg.Sender__c; w.text = msg.Text__c;
            w.imageUrl = msg.Image_URL__c; w.sendAutomatically = msg.Send_Automatically__c;
            w.typingSeconds = msg.Typing_Seconds__c; w.pauseSeconds = msg.Pause_Seconds__c;
            w.deliveryStatus = msg.Delivery_Status__c; w.tapback = msg.Tapback__c;
            w.effect = msg.Effect__c; w.awaitPhoto = msg.Await_Photo__c;
            w.reactToPrevious = msg.React_To_Previous__c;
            w.replyToStep = msg.Reply_To_Step__c;
            byId.get(msg.Conversation__c).messages.add(w);
        }
        for (Id cid : order) { t.conversations.add(byId.get(cid)); }

        t.endpointUrl = demoEndpointUrl(d.Config_Name__c);
        t.defaultUrl = siteBaseUrl();
        t.versionToken = treeToken(t);
        return t;
    }

    // MARK: - Write

    /**
     * Saves the tree while preserving child record identities. A version token
     * prevents one browser session from silently overwriting another.
     */
    @AuraEnabled
    public static DemoTree saveDemo(String treeJson) {
        Savepoint sp = Database.setSavepoint();
        try {
            DemoTree t = (DemoTree) JSON.deserialize(treeJson, DemoTree.class);
            if (t == null || t.demo == null || String.isBlank(t.demo.id)) {
                throw handled('Select a valid demo before saving.');
            }

            Id demoId;
            try {
                demoId = (Id) t.demo.id;
            } catch (Exception invalidId) {
                throw handled('The selected demo is no longer valid. Refresh and try again.');
            }

            List<iMessage_Demo__c> locked = [
                SELECT Id FROM iMessage_Demo__c WHERE Id = :demoId LIMIT 1 FOR UPDATE
            ];
            if (locked.isEmpty()) {
                throw handled('That demo no longer exists. Refresh the builder.');
            }

            DemoTree current = loadDemo(demoId);
            if (String.isBlank(t.versionToken) || t.versionToken != current.versionToken) {
                throw handled(
                    'This demo changed after you opened it. Refresh before saving so you do not overwrite newer work.'
                );
            }

            normalizeTree(t);

            Map<Id, iMessage_Notification__c> existingNotifs =
                new Map<Id, iMessage_Notification__c>([
                    SELECT Id FROM iMessage_Notification__c WHERE Demo__c = :demoId
                ]);
            Map<Id, iMessage_Conversation__c> existingConvs =
                new Map<Id, iMessage_Conversation__c>([
                    SELECT Id FROM iMessage_Conversation__c WHERE Demo__c = :demoId
                ]);
            Set<Id> existingConvIds = existingConvs.keySet();
            Map<Id, iMessage_Message__c> existingMsgs =
                new Map<Id, iMessage_Message__c>([
                    SELECT Id FROM iMessage_Message__c WHERE Conversation__c IN :existingConvIds
                ]);

            iMessage_Demo__c d = new iMessage_Demo__c(
                Id = demoId,
                Name = blankTo(t.demo.name, 'Untitled demo'),
                Config_Name__c = t.demo.configName,
                Is_Active__c = t.demo.isActive == true,
                Show_In_App__c = t.demo.showInApp == true,
                // A restricted picklist rejects '', so an empty pick has to land as null.
                Bubble_Style__c = blankToNull(t.demo.bubbleStyle),
                SB_Carrier__c = t.demo.carrier,
                SB_Signal_Bars__c = t.demo.signalBars,
                SB_WiFi_Strength__c = t.demo.wifiStrength,
                SB_Show_WiFi__c = t.demo.showWifi == true,
                SB_Battery_Level__c = t.demo.batteryLevel,
                SB_Is_Charging__c = t.demo.isCharging == true
            );
            update d;

            // Only one demo can be the one the endpoint serves by default.
            if (d.Is_Active__c) {
                List<iMessage_Demo__c> others = [
                    SELECT Id FROM iMessage_Demo__c WHERE Is_Active__c = TRUE AND Id != :d.Id
                ];
                for (iMessage_Demo__c o : others) { o.Is_Active__c = false; }
                if (!others.isEmpty()) { update others; }
            }

            List<iMessage_Notification__c> notifs = new List<iMessage_Notification__c>();
            Integer i = 0;
            for (Notif n : t.notifications) {
                iMessage_Notification__c row = new iMessage_Notification__c(
                    Name = blankTo(n.title, 'Notification'), Demo__c = d.Id, Sort_Order__c = ++i,
                    Icon_Name__c = n.iconName, Icon_Color__c = n.iconColor,
                    Document_Icon__c = n.documentIcon,
                    Title__c = n.title, Message__c = n.message,
                    Time_Ago__c = n.timeAgo, Conversation_Key__c = n.conversationKey,
                    Call_Key__c = n.callKey, After_Seconds__c = n.afterSeconds
                );
                row.Id = ownedId(n.id, existingNotifs.keySet(), 'notification');
                notifs.add(row);
            }
            if (!notifs.isEmpty()) { upsert notifs; }
            Set<Id> keptNotifIds = new Set<Id>();
            for (iMessage_Notification__c row : notifs) { keptNotifIds.add(row.Id); }

            List<iMessage_Conversation__c> convs = new List<iMessage_Conversation__c>();
            i = 0;
            for (Conversation c : t.conversations) {
                iMessage_Conversation__c row = new iMessage_Conversation__c(
                    Name = blankTo(c.contactName, 'Conversation'), Demo__c = d.Id, Sort_Order__c = ++i,
                    Conversation_Key__c = c.conversationKey, Contact_Name__c = c.contactName,
                    Contact_Subtitle__c = c.contactSubtitle, Avatar_URL__c = c.avatarUrl,
                    Last_Message_Preview__c = c.lastMessagePreview, Last_Message_Time__c = c.lastMessageTime,
                    Unread_Count__c = c.unreadCount, Is_SMS__c = c.isSMS == true,
                    Is_Muted__c = c.isMuted == true, Is_Forwarded__c = c.isForwarded == true,
                    Transcript_Speed__c = c.transcriptSpeed, Draft_Text__c = c.draftText,
                    Show_In_Phone__c = c.showInPhone == true,
                    Phone_Sort_Order__c = c.phoneSortOrder,
                    // A restricted picklist rejects '', so an empty pick has to land as null.
                    Phone_Label__c = blankToNull(c.phoneLabel),
                    Call_Subtitle__c = c.callSubtitle,
                    Call_Background_URL__c = c.callBackgroundUrl,
                    Ring_Seconds__c = c.ringSeconds,
                    Notification_After_Seconds__c = c.notificationAfterSeconds,
                    // A restricted picklist rejects '', so an empty pick has to land as null.
                    Agent_Connection__c = blankToNull(c.voiceConnection),
                    Agent_My_Domain__c = c.voiceMyDomain,
                    Agent_Id__c = c.voiceAgentId,
                    Agent_ES_Developer_Name__c = c.voiceEsDeveloperName,
                    Agent_Org_Id__c = c.voiceOrgId,
                    Agent_SCRT_URL__c = c.voiceScrtUrl,
                    Agent_Greeting__c = c.voiceGreeting
                );
                row.Id = ownedId(c.id, existingConvs.keySet(), 'conversation');
                convs.add(row);
            }
            if (!convs.isEmpty()) { upsert convs; }
            Set<Id> keptConvIds = new Set<Id>();
            for (iMessage_Conversation__c row : convs) { keptConvIds.add(row.Id); }

            List<iMessage_Message__c> msgs = new List<iMessage_Message__c>();
            for (Integer ci = 0; ci < convs.size(); ci++) {
                Integer mi = 0;
                for (Msg m : t.conversations[ci].messages) {
                    iMessage_Message__c row = new iMessage_Message__c(
                        Name = label(m), Conversation__c = convs[ci].Id, Sort_Order__c = ++mi,
                        Sender__c = m.sender, Text__c = m.text, Image_URL__c = m.imageUrl,
                        Send_Automatically__c = m.sendAutomatically != false,
                        Typing_Seconds__c = m.typingSeconds, Pause_Seconds__c = m.pauseSeconds,
                        Delivery_Status__c = m.deliveryStatus, Tapback__c = m.tapback,
                        Effect__c = m.effect, Await_Photo__c = m.awaitPhoto == true,
                        React_To_Previous__c = m.reactToPrevious,
                        Reply_To_Step__c = m.replyToStep
                    );
                    row.Id = ownedId(m.id, existingMsgs.keySet(), 'message');
                    msgs.add(row);
                }
            }
            if (!msgs.isEmpty()) { upsert msgs; }
            Set<Id> keptMsgIds = new Set<Id>();
            for (iMessage_Message__c row : msgs) { keptMsgIds.add(row.Id); }

            List<iMessage_Message__c> removedMsgs = new List<iMessage_Message__c>();
            for (Id existingId : existingMsgs.keySet()) {
                if (!keptMsgIds.contains(existingId)) {
                    removedMsgs.add(existingMsgs.get(existingId));
                }
            }
            if (!removedMsgs.isEmpty()) { delete removedMsgs; }

            List<iMessage_Conversation__c> removedConvs = new List<iMessage_Conversation__c>();
            for (Id existingId : existingConvs.keySet()) {
                if (!keptConvIds.contains(existingId)) {
                    removedConvs.add(existingConvs.get(existingId));
                }
            }
            if (!removedConvs.isEmpty()) { delete removedConvs; }

            List<iMessage_Notification__c> removedNotifs = new List<iMessage_Notification__c>();
            for (Id existingId : existingNotifs.keySet()) {
                if (!keptNotifIds.contains(existingId)) {
                    removedNotifs.add(existingNotifs.get(existingId));
                }
            }
            if (!removedNotifs.isEmpty()) { delete removedNotifs; }

            return loadDemo(d.Id);
        } catch (Exception e) {
            Database.rollback(sp);
            throw handled(e.getMessage());
        }
    }

    @AuraEnabled
    public static String createDemo(String name) {
        String displayName = String.isBlank(name) ? 'New demo' : name.trim().left(80);
        iMessage_Demo__c d = new iMessage_Demo__c(
            Name = displayName,
            Config_Name__c = uniqueConfigName(displayName),
            SB_Carrier__c = 'T-Mobile', SB_Signal_Bars__c = 4, SB_WiFi_Strength__c = 3,
            SB_Show_WiFi__c = true, SB_Battery_Level__c = 0.82
        );
        insert d;
        return d.Id;
    }

    @AuraEnabled
    public static String cloneDemo(String demoId, String versionToken, String name) {
        Savepoint sp = Database.setSavepoint();
        try {
            List<iMessage_Demo__c> locked = [
                SELECT Id FROM iMessage_Demo__c WHERE Id = :demoId LIMIT 1 FOR UPDATE
            ];
            if (locked.isEmpty()) {
                throw handled('That demo no longer exists.');
            }
            DemoTree source = loadDemo(demoId);
            if (String.isBlank(versionToken) || versionToken != source.versionToken) {
                throw handled('This demo changed after you opened it. Refresh before duplicating it.');
            }

            String displayName = String.isBlank(name)
                ? source.demo.name + ' copy'
                : name.trim().left(80);
            String newId = createDemo(displayName);
            DemoTree target = loadDemo(newId);

            source.demo.id = newId;
            source.demo.name = displayName;
            source.demo.configName = target.demo.configName;
            source.demo.isActive = false;
            source.demo.showInApp = false;
            source.versionToken = target.versionToken;
            source.endpointUrl = target.endpointUrl;
            source.defaultUrl = target.defaultUrl;
            for (Notif n : source.notifications) { n.id = null; }
            for (Conversation c : source.conversations) {
                c.id = null;
                for (Msg m : c.messages) { m.id = null; }
            }

            DemoTree saved = saveDemo(JSON.serialize(source));
            return saved.demo.id;
        } catch (Exception e) {
            Database.rollback(sp);
            throw handled(e.getMessage());
        }
    }

    @AuraEnabled
    public static void deleteDemo(String demoId, String versionToken) {
        List<iMessage_Demo__c> locked = [
            SELECT Id FROM iMessage_Demo__c WHERE Id = :demoId LIMIT 1 FOR UPDATE
        ];
        if (locked.isEmpty()) {
            throw handled('That demo no longer exists.');
        }
        DemoTree current = loadDemo(demoId);
        if (String.isBlank(versionToken) || versionToken != current.versionToken) {
            throw handled('This demo changed after you opened it. Refresh before deleting it.');
        }
        delete locked;
    }

    // MARK: - Normalization and concurrency

    private static void normalizeTree(DemoTree t) {
        if (t.notifications == null) { t.notifications = new List<Notif>(); }
        if (t.conversations == null) { t.conversations = new List<Conversation>(); }

        t.demo.name = trimToNull(t.demo.name);
        t.demo.configName = trimToNull(t.demo.configName);
        t.demo.signalBars = clamp(t.demo.signalBars, 0, 4);
        t.demo.wifiStrength = clamp(t.demo.wifiStrength, 0, 3);
        t.demo.batteryLevel = clamp(t.demo.batteryLevel, 0, 1);

        for (Conversation c : t.conversations) {
            c.conversationKey = trimToNull(c.conversationKey);
            c.contactName = trimToNull(c.contactName);
            if (c.messages == null) { c.messages = new List<Msg>(); }
            c.unreadCount = clamp(c.unreadCount, 0, 999);
            c.transcriptSpeed = clamp(c.transcriptSpeed, 1, 99999);
            c.phoneLabel = trimToNull(c.phoneLabel);
            c.ringSeconds = clamp(c.ringSeconds, 0, 999.9);
            c.notificationAfterSeconds = clamp(c.notificationAfterSeconds, 0, 999.9);
            // Pasted credentials often carry a stray space or newline, and the
            // SDK takes them literally.
            c.voiceMyDomain = trimToNull(c.voiceMyDomain);
            c.voiceAgentId = trimToNull(c.voiceAgentId);
            c.voiceEsDeveloperName = trimToNull(c.voiceEsDeveloperName);
            c.voiceOrgId = trimToNull(c.voiceOrgId);
            c.voiceScrtUrl = trimToNull(c.voiceScrtUrl);
            c.voiceGreeting = trimToNull(c.voiceGreeting);
            for (Msg m : c.messages) {
                m.typingSeconds = clamp(m.typingSeconds, 0, 999.9);
                m.pauseSeconds = clamp(m.pauseSeconds, 0, 999.9);
            }
        }
        for (Notif n : t.notifications) {
            n.conversationKey = trimToNull(n.conversationKey);
            n.callKey = trimToNull(n.callKey);
            n.afterSeconds = clamp(n.afterSeconds, 0, 999.9);
        }
        renumberPhoneOrder(t.conversations);
    }

    /**
     * Favorites keeps its own running order, and the app numbers `contacts[].id`
     * by position — so the stored order has to stay dense. Whatever the browser
     * sent is treated as a preference and rewritten to 1..N here; a conversation
     * that is not in the Phone app carries no number at all.
     */
    private static void renumberPhoneOrder(List<Conversation> convs) {
        List<Conversation> shown = new List<Conversation>();
        for (Conversation c : convs) {
            if (c.showInPhone == true) { shown.add(c); }
            else { c.phoneSortOrder = null; }
        }
        // Insertion sort: the list is a handful of rows and this keeps ties in
        // the order they arrived, which is the Messages order.
        for (Integer i = 1; i < shown.size(); i++) {
            Conversation moving = shown[i];
            Integer j = i - 1;
            while (j >= 0 && sortsAfter(shown[j], moving)) {
                shown[j + 1] = shown[j];
                j--;
            }
            shown[j + 1] = moving;
        }
        for (Integer i = 0; i < shown.size(); i++) { shown[i].phoneSortOrder = i + 1; }
    }

    /** A conversation with no requested position goes behind one that has one. */
    private static Boolean sortsAfter(Conversation left, Conversation right) {
        if (left.phoneSortOrder == right.phoneSortOrder) { return false; }
        if (left.phoneSortOrder == null)  { return true;  }
        if (right.phoneSortOrder == null) { return false; }
        return left.phoneSortOrder > right.phoneSortOrder;
    }

    private static Id ownedId(String rawId, Set<Id> allowedIds, String recordType) {
        if (String.isBlank(rawId)) { return null; }
        Id parsedId;
        try {
            parsedId = (Id) rawId;
        } catch (Exception invalidId) {
            throw handled('A ' + recordType + ' reference is invalid. Refresh the builder.');
        }
        if (!allowedIds.contains(parsedId)) {
            throw handled('A ' + recordType + ' changed outside this demo. Refresh the builder.');
        }
        return parsedId;
    }

    private static String treeToken(DemoTree t) {
        String endpoint = t.endpointUrl;
        String defaultEndpoint = t.defaultUrl;
        String version = t.versionToken;
        t.endpointUrl = null;
        t.defaultUrl = null;
        t.versionToken = null;
        String payload = JSON.serialize(t);
        t.endpointUrl = endpoint;
        t.defaultUrl = defaultEndpoint;
        t.versionToken = version;
        return EncodingUtil.convertToHex(
            Crypto.generateDigest('SHA-256', Blob.valueOf(payload))
        );
    }

    private static String uniqueConfigName(String displayName) {
        String base = slugify(displayName);
        String pattern = base + '%';
        Set<String> used = new Set<String>();
        for (iMessage_Demo__c d : [
            SELECT Config_Name__c
            FROM iMessage_Demo__c
            WHERE Config_Name__c LIKE :pattern
        ]) {
            if (String.isNotBlank(d.Config_Name__c)) {
                used.add(d.Config_Name__c.toLowerCase());
            }
        }

        String candidate = base;
        Integer suffixNumber = 2;
        while (used.contains(candidate.toLowerCase())) {
            String suffix = '-' + String.valueOf(suffixNumber++);
            Integer rootLength = 120 - suffix.length();
            String root = base.length() > rootLength ? base.substring(0, rootLength) : base;
            candidate = root + suffix;
        }
        return candidate;
    }

    private static String slugify(String value) {
        String slug = String.isBlank(value)
            ? 'new-demo'
            : value.toLowerCase().replaceAll('[^a-z0-9]+', '-').replaceAll('(^-+|-+$)', '');
        if (String.isBlank(slug)) { slug = 'new-demo'; }
        return slug.length() > 100 ? slug.substring(0, 100) : slug;
    }

    private static String trimToNull(String value) {
        return String.isBlank(value) ? null : value.trim();
    }

    private static Decimal clamp(Decimal value, Decimal minimum, Decimal maximum) {
        if (value == null) { return null; }
        if (value < minimum) { return minimum; }
        if (value > maximum) { return maximum; }
        return value;
    }

    private static AuraHandledException handled(String message) {
        AuraHandledException error = new AuraHandledException(message);
        error.setMessage(message);
        return error;
    }

    // MARK: - Endpoint

    /**
     * Stable URL for a demo. Always includes ?id= so multiple demos can be
     * bookmarked and tested in parallel. isActive is kept for Aura callers
     * but no longer changes the returned URL.
     */
    @AuraEnabled(cacheable=true)
    public static String endpointUrl(String configName, Boolean isActive) {
        return demoEndpointUrl(configName);
    }

    private static String demoEndpointUrl(String configName) {
        String base = siteBaseUrl();
        if (base == null) { return null; }
        if (String.isBlank(configName)) { return base; }
        return base + '?id=' + EncodingUtil.urlEncode(configName, 'UTF-8');
    }

    private static String siteBaseUrl() {
        List<DomainSite> sites = [
            SELECT Domain.Domain, PathPrefix
            FROM DomainSite
            WHERE Site.UrlPathPrefix != NULL
            LIMIT 1
        ];
        if (sites.isEmpty()) { return null; }
        String prefix = sites[0].PathPrefix == null ? '' : sites[0].PathPrefix.replaceAll('^/+', '');
        return 'https://' + sites[0].Domain.Domain + '/' + prefix + '/DemoConfig';
    }

    private static String blankToNull(String v) {
        return String.isBlank(v) ? null : v;
    }

    private static String blankTo(String v, String fallback) {
        return String.isBlank(v) ? fallback : v.left(80);
    }

    private static String label(Msg m) {
        if (String.isNotBlank(m.text)) { return m.text.left(70); }
        if (String.isNotBlank(m.reactToPrevious)) { return 'reacts ' + m.reactToPrevious; }
        if (m.awaitPhoto == true) { return 'awaits photo'; }
        return 'step';
    }
}