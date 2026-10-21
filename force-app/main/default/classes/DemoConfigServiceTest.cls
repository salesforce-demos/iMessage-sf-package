@IsTest
private class DemoConfigServiceTest {

    private static iMessage_Demo__c makeDemo(Boolean active) {
        iMessage_Demo__c d = new iMessage_Demo__c(
            Name = 'Claim demo',
            Config_Name__c = 'claim-demo',
            Is_Active__c = active,
            SB_Carrier__c = 'T-Mobile',
            SB_Signal_Bars__c = 4,
            SB_Battery_Level__c = 0.82
        );
        insert d;

        insert new iMessage_Notification__c(
            Name = 'Nora asks for a photo', Demo__c = d.Id, Sort_Order__c = 1,
            Icon_Name__c = 'message.fill', Icon_Color__c = '#4CD964',
            Title__c = 'Nora Bennett', Message__c = 'Can you send me a photo?',
            Time_Ago__c = 'now', Conversation_Key__c = 'nora'
        );

        iMessage_Conversation__c c = new iMessage_Conversation__c(
            Name = 'Nora Bennett', Demo__c = d.Id, Sort_Order__c = 1,
            Conversation_Key__c = 'nora', Contact_Name__c = 'Nora Bennett',
            Unread_Count__c = 2, Transcript_Speed__c = 600, Is_SMS__c = false,
            Show_In_Phone__c = true, Phone_Sort_Order__c = 1, Phone_Label__c = 'iPhone',
            Avatar_URL__c = 'https://example.com/nora.png', Ring_Seconds__c = 4
        );
        insert c;

        // Second thread, deliberately kept out of the Phone app.
        insert new iMessage_Conversation__c(
            Name = 'Trailhead', Demo__c = d.Id, Sort_Order__c = 2,
            Conversation_Key__c = 'trailhead', Contact_Name__c = 'Trailhead',
            Show_In_Phone__c = false
        );

        insert new List<iMessage_Message__c>{
            new iMessage_Message__c(Name = '1', Conversation__c = c.Id, Sort_Order__c = 1,
                Sender__c = 'them', Text__c = 'Hey', Send_Automatically__c = true, Typing_Seconds__c = 1.1),
            new iMessage_Message__c(Name = '2', Conversation__c = c.Id, Sort_Order__c = 2,
                Sender__c = 'me', Await_Photo__c = true),
            new iMessage_Message__c(Name = '3', Conversation__c = c.Id, Sort_Order__c = 3,
                Sender__c = 'them', React_To_Previous__c = 'heart'),
            new iMessage_Message__c(Name = '4', Conversation__c = c.Id, Sort_Order__c = 4,
                Sender__c = 'me', Text__c = 'Answering that', Reply_To_Step__c = 1)
        };
        return d;
    }

    @IsTest
    static void buildsTheActiveDemoWhenNoKeyIsGiven() {
        makeDemo(true);

        Test.startTest();
        String payload = DemoConfigService.buildJson(null);
        Test.stopTest();

        Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(payload);
        Assert.areEqual('claim-demo', root.get('configName'));
        Assert.isFalse(root.containsKey('call'),
            'the call belongs to a contact now, not to the demo');
        Assert.isFalse(root.containsKey('directCall'), 'the app opens on the Phone tab');

        List<Object> convs = (List<Object>) root.get('conversations');
        Assert.areEqual(2, convs.size());
        Map<String, Object> nora = (Map<String, Object>) convs[0];
        Assert.areEqual('nora', nora.get('id'));

        List<Object> msgs = (List<Object>) nora.get('messages');
        Assert.areEqual(4, msgs.size(), 'every scripted step should survive');
        Assert.areEqual(true, ((Map<String, Object>) msgs[1]).get('awaitPhoto'));
        Assert.areEqual('heart', ((Map<String, Object>) msgs[2]).get('reactToPrevious'));
        Assert.areEqual(1, ((Map<String, Object>) msgs[3]).get('replyTo'),
            'a reply must carry the step it quotes');
        Assert.isFalse(((Map<String, Object>) msgs[0]).containsKey('replyTo'),
            'a normal step must not carry replyTo at all');
    }

    @IsTest
    static void onlyConversationsShownInPhoneBecomeContacts() {
        makeDemo(true);

        Test.startTest();
        String payload = DemoConfigService.buildJson(null);
        Test.stopTest();

        Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(payload);
        List<Object> contacts = (List<Object>) root.get('contacts');
        Assert.areEqual(1, contacts.size(), 'the unticked thread must not reach the Phone app');

        Map<String, Object> nora = (Map<String, Object>) contacts[0];
        Assert.areEqual(1, nora.get('id'), 'ids are the position in the list, starting at 1');
        Assert.areEqual('Nora Bennett', nora.get('name'));
        Assert.areEqual('iPhone', nora.get('phoneLabel'));
        Assert.areEqual('nora', nora.get('conversationId'),
            'a contact must point at a conversation that exists');
        Assert.areEqual('https://example.com/nora.png', nora.get('avatar'),
            'the contact and the thread must share one avatar');
        Assert.areEqual(4, nora.get('ringSeconds'));
        Assert.isFalse(nora.containsKey('subtitle'),
            'a blank subtitle stays absent so the app writes "calling <label>…" itself');
    }

    @IsTest
    static void aContactWithoutAMyDomainCarriesNoVoiceLine() {
        makeDemo(true);

        Map<String, Object> root =
            (Map<String, Object>) JSON.deserializeUntyped(DemoConfigService.buildJson(null));
        Map<String, Object> nora = (Map<String, Object>) ((List<Object>) root.get('contacts'))[0];
        Assert.isFalse(nora.containsKey('voice'),
            'no My Domain means the fake call, so the key must stay out');
    }

    @IsTest
    static void aContactWithAMyDomainCarriesItsVoiceLine() {
        makeDemo(true);
        iMessage_Conversation__c c = [
            SELECT Id FROM iMessage_Conversation__c WHERE Conversation_Key__c = 'nora' LIMIT 1
        ];
        c.Agent_Connection__c = 'agentAPI';
        c.Agent_My_Domain__c = 'https://acme.my.salesforce.com';
        c.Agent_Id__c = '0XxgK000002J0w1SAC';
        c.Agent_Greeting__c = 'Hi, this is Nora.';
        update c;

        Map<String, Object> root =
            (Map<String, Object>) JSON.deserializeUntyped(DemoConfigService.buildJson(null));
        Map<String, Object> nora = (Map<String, Object>) ((List<Object>) root.get('contacts'))[0];
        Map<String, Object> voice = (Map<String, Object>) nora.get('voice');
        Assert.areEqual('agentAPI', voice.get('connection'));
        Assert.areEqual('https://acme.my.salesforce.com', voice.get('myDomain'));
        Assert.areEqual('0XxgK000002J0w1SAC', voice.get('agentId'));
        Assert.areEqual('Hi, this is Nora.', voice.get('greeting'));
        Assert.isFalse(voice.containsKey('esDeveloperName'),
            'blank Messaging fields stay out of an Agent API voice line');
    }

    @IsTest
    static void aBlankPhoneLabelFallsBackToMobile() {
        makeDemo(true);
        iMessage_Conversation__c c = [
            SELECT Id FROM iMessage_Conversation__c WHERE Conversation_Key__c = 'nora' LIMIT 1
        ];
        c.Phone_Label__c = null;
        update c;

        Map<String, Object> root =
            (Map<String, Object>) JSON.deserializeUntyped(DemoConfigService.buildJson(null));
        List<Object> contacts = (List<Object>) root.get('contacts');
        Assert.areEqual('mobile', ((Map<String, Object>) contacts[0]).get('phoneLabel'));
    }

    @IsTest
    static void contactIdsCloseTheGapLeftByAnUntickedThread() {
        iMessage_Demo__c d = makeDemo(true);
        insert new iMessage_Conversation__c(
            Name = 'Delivery', Demo__c = d.Id, Sort_Order__c = 3,
            Conversation_Key__c = 'delivery', Contact_Name__c = '+1 (415) 555-0148',
            Show_In_Phone__c = true, Phone_Sort_Order__c = 2
        );

        List<Object> contacts = servedContacts();
        Assert.areEqual(2, contacts.size());
        // Trailhead sits between them in Sort Order but is not in the Phone app,
        // so the numbering must run 1, 2 rather than skipping to 3.
        Assert.areEqual(1, ((Map<String, Object>) contacts[0]).get('id'));
        Assert.areEqual(2, ((Map<String, Object>) contacts[1]).get('id'));
        Assert.areEqual('delivery', ((Map<String, Object>) contacts[1]).get('conversationId'));
    }

    @IsTest
    static void favoritesFollowTheirOwnOrderNotTheMessagesOne() {
        iMessage_Demo__c d = makeDemo(true);
        // Last in Messages, first in Favorites — the case the demo actually ships.
        insert new iMessage_Conversation__c(
            Name = 'Delivery', Demo__c = d.Id, Sort_Order__c = 3,
            Conversation_Key__c = 'delivery', Contact_Name__c = 'Canada Goose',
            Show_In_Phone__c = true, Phone_Sort_Order__c = 1
        );
        // Nora is Sort_Order 1 but asked for the second slot in Favorites.
        iMessage_Conversation__c nora = [
            SELECT Id FROM iMessage_Conversation__c WHERE Conversation_Key__c = 'nora' LIMIT 1
        ];
        nora.Phone_Sort_Order__c = 2;
        update nora;

        Map<String, Object> root =
            (Map<String, Object>) JSON.deserializeUntyped(DemoConfigService.buildJson(null));

        List<Object> convs = (List<Object>) root.get('conversations');
        Assert.areEqual('nora', ((Map<String, Object>) convs[0]).get('id'),
            'the Messages list still follows Sort Order');

        List<Object> contacts = (List<Object>) root.get('contacts');
        Assert.areEqual('delivery', ((Map<String, Object>) contacts[0]).get('conversationId'),
            'Favorites must follow Phone Sort Order, not the Messages list');
        Assert.areEqual(1, ((Map<String, Object>) contacts[0]).get('id'));
        Assert.areEqual('nora', ((Map<String, Object>) contacts[1]).get('conversationId'));
        Assert.areEqual(2, ((Map<String, Object>) contacts[1]).get('id'));
    }

    @IsTest
    static void aContactWithNoPhoneOrderGoesLast() {
        iMessage_Demo__c d = makeDemo(true);
        insert new iMessage_Conversation__c(
            Name = 'Delivery', Demo__c = d.Id, Sort_Order__c = 3,
            Conversation_Key__c = 'delivery', Contact_Name__c = 'Canada Goose',
            Show_In_Phone__c = true
        );
        // Nora keeps Phone Sort Order 1 from makeDemo; delivery asked for nothing,
        // so it queues behind her even though nothing else competes for a slot.
        List<Object> contacts = servedContacts();
        Assert.areEqual(2, contacts.size());
        Assert.areEqual('nora', ((Map<String, Object>) contacts[0]).get('conversationId'));
        Assert.areEqual('delivery', ((Map<String, Object>) contacts[1]).get('conversationId'));
    }

    @IsTest
    static void aBannerWithACallRidesWithThatContact() {
        iMessage_Demo__c d = makeDemo(true);
        insert new iMessage_Notification__c(
            Name = 'Package delivered', Demo__c = d.Id, Sort_Order__c = 2,
            Icon_Name__c = 'message.fill', Title__c = 'Canada Goose',
            Message__c = 'Your package was delivered.', Time_Ago__c = 'now',
            Conversation_Key__c = 'nora', Call_Key__c = 'nora', After_Seconds__c = 5
        );

        Map<String, Object> root =
            (Map<String, Object>) JSON.deserializeUntyped(DemoConfigService.buildJson(null));

        Map<String, Object> nora = (Map<String, Object>) ((List<Object>) root.get('contacts'))[0];
        List<Object> own = (List<Object>) nora.get('notifications');
        Assert.areEqual(1, own.size(), 'the banner must ride with the call it names');
        Map<String, Object> banner = (Map<String, Object>) own[0];
        Assert.areEqual('Canada Goose', banner.get('title'));
        Assert.areEqual(5, banner.get('afterSeconds'), 'its own delay has to reach the app');
        Assert.areEqual('nora', banner.get('conversationId'),
            'tapping it still opens the thread it points at');
        Assert.isFalse(banner.containsKey('callKey'),
            'the call it belongs to is the array it sits in, not a key in the payload');

        List<Object> shared = (List<Object>) root.get('callNotifications');
        Assert.areEqual(1, shared.size(), 'only the one without a call stays in the shared list');
        Assert.areEqual('Nora Bennett', ((Map<String, Object>) shared[0]).get('title'));
    }

    @IsTest
    static void aCallWithNoBannersOfItsOwnCarriesNoList() {
        makeDemo(true);

        List<Object> contacts = servedContacts();
        Assert.isFalse(((Map<String, Object>) contacts[0]).containsKey('notifications'),
            'an absent list is what sends the app back to the shared one');
    }

    @IsTest
    static void everyBannerOwnedByACallEmptiesTheSharedList() {
        iMessage_Demo__c d = makeDemo(true);
        iMessage_Notification__c only = [
            SELECT Id FROM iMessage_Notification__c WHERE Demo__c = :d.Id LIMIT 1
        ];
        only.Call_Key__c = 'nora';
        update only;

        Map<String, Object> root =
            (Map<String, Object>) JSON.deserializeUntyped(DemoConfigService.buildJson(null));
        Assert.isFalse(root.containsKey('callNotifications'),
            'nothing left over means the key should not be in the payload at all');
        Map<String, Object> nora = (Map<String, Object>) ((List<Object>) root.get('contacts'))[0];
        Assert.areEqual(1, ((List<Object>) nora.get('notifications')).size());
    }

    @IsTest
    static void bannersOfOneCallKeepTheOrderTheyWereWrittenIn() {
        iMessage_Demo__c d = makeDemo(true);
        insert new List<iMessage_Notification__c>{
            new iMessage_Notification__c(
                Name = 'Second', Demo__c = d.Id, Sort_Order__c = 3,
                Title__c = 'Second', Message__c = 'Second', Conversation_Key__c = 'nora',
                Call_Key__c = 'nora', After_Seconds__c = 16),
            new iMessage_Notification__c(
                Name = 'First', Demo__c = d.Id, Sort_Order__c = 2,
                Title__c = 'First', Message__c = 'First', Conversation_Key__c = 'nora',
                Call_Key__c = 'nora')
        };

        Map<String, Object> nora = (Map<String, Object>) servedContacts()[0];
        List<Object> own = (List<Object>) nora.get('notifications');
        Assert.areEqual(2, own.size());
        // Sort Order is the running order: a banner with no time of its own
        // follows the one above it, so the author's order is the schedule.
        Assert.areEqual('First', ((Map<String, Object>) own[0]).get('title'));
        Assert.areEqual('Second', ((Map<String, Object>) own[1]).get('title'));
        Assert.isFalse(((Map<String, Object>) own[0]).containsKey('afterSeconds'),
            'a blank delay must stay absent so the app applies its own rhythm');
    }

    private static List<Object> servedContacts() {
        Map<String, Object> root =
            (Map<String, Object>) JSON.deserializeUntyped(DemoConfigService.buildJson(null));
        return (List<Object>) root.get('contacts');
    }

    private static Boolean servedIsSMS(String demoKey) {
        Map<String, Object> root =
            (Map<String, Object>) JSON.deserializeUntyped(DemoConfigService.buildJson(demoKey));
        List<Object> convs = (List<Object>) root.get('conversations');
        return (Boolean) ((Map<String, Object>) convs[0]).get('isSMS');
    }

    @IsTest
    static void aBlankBubbleStyleLeavesTheColourToTheConversation() {
        makeDemo(true);
        Assert.areEqual(false, servedIsSMS(null),
            'with nothing forced the conversation\'s own Is SMS must come through');
    }

    @IsTest
    static void bubbleStyleSMSTurnsEveryConversationGreen() {
        iMessage_Demo__c d = makeDemo(true);
        d.Bubble_Style__c = 'SMS';
        update d;
        Assert.areEqual(true, servedIsSMS(null), 'the demo-wide switch must win over the conversation');
    }

    @IsTest
    static void bubbleStyleIMessageTurnsEveryConversationBlue() {
        iMessage_Demo__c d = makeDemo(true);
        // Green at the conversation level, so only the override can make it blue.
        iMessage_Conversation__c c = [
            SELECT Id FROM iMessage_Conversation__c WHERE Conversation_Key__c = 'nora' LIMIT 1
        ];
        c.Is_SMS__c = true;
        update c;
        d.Bubble_Style__c = 'iMessage';
        update d;
        Assert.areEqual(false, servedIsSMS(null), 'the demo-wide switch must win over the conversation');
    }

    @IsTest
    static void findsADemoByItsConfigName() {
        makeDemo(false);
        String payload = DemoConfigService.buildJson('claim-demo');
        Assert.isTrue(payload.contains('"configName":"claim-demo"'));
    }

    @IsTest
    static void omitsEmptyOptionalKeys() {
        makeDemo(true);
        String payload = DemoConfigService.buildJson(null);
        Assert.isFalse(payload.contains('null'), 'null values must not reach the app');
        Assert.isFalse(payload.contains('"draftText"'), 'blank optionals should be absent');
    }

    @IsTest
    static void raisesWhenNothingIsActive() {
        try {
            DemoConfigService.buildJson(null);
            Assert.fail('expected ConfigNotFoundException');
        } catch (DemoConfigService.ConfigNotFoundException e) {
            Assert.isTrue(e.getMessage().contains('Is Active'));
        }
    }

    @IsTest
    static void pageReturnsErrorJsonInsteadOfBlowingUp() {
        Test.setCurrentPage(Page.DemoConfig);
        String payload = new DemoConfigController().getConfigJson();
        Assert.isTrue(payload.contains('error'), 'a missing demo should still return JSON');
    }

    @IsTest
    static void pageServesTheRequestedDemo() {
        makeDemo(false);
        Test.setCurrentPage(Page.DemoConfig);
        ApexPages.currentPage().getParameters().put('id', 'claim-demo');
        Assert.isTrue(new DemoConfigController().getConfigJson().contains('Nora Bennett'));
    }

    @IsTest
    static void theListOnlyCarriesDemosTickedShowInApp() {
        iMessage_Demo__c shown = makeDemo(false);
        shown.Show_In_App__c = true;
        update shown;
        insert new iMessage_Demo__c(Name = 'Hidden demo', Config_Name__c = 'hidden-demo');

        Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(DemoConfigService.buildListJson());
        List<Object> demos = (List<Object>) root.get('demos');

        Assert.areEqual(1, demos.size());
        Map<String, Object> only = (Map<String, Object>) demos[0];
        Assert.areEqual('Claim demo', only.get('name'));
        Assert.areEqual('claim-demo', only.get('id'));
    }

    @IsTest
    static void pageServesTheListWhenAsked() {
        Test.setCurrentPage(Page.DemoConfig);
        ApexPages.currentPage().getParameters().put('list', '1');
        Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(new DemoConfigController().getConfigJson());
        Assert.isTrue(root.containsKey('demos'));
    }
}
