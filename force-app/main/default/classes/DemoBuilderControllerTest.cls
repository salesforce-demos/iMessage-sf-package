@IsTest
private class DemoBuilderControllerTest {

    private static String seed() {
        String demoId = DemoBuilderController.createDemo('Builder test');
        DemoBuilderController.DemoTree t = DemoBuilderController.loadDemo(demoId);

        DemoBuilderController.Conversation c = new DemoBuilderController.Conversation();
        c.conversationKey = 'nora';
        c.contactName = 'Nora Bennett';
        c.unreadCount = 2;
        c.showInPhone = true;
        c.phoneLabel = 'iPhone';
        c.ringSeconds = 4;
        DemoBuilderController.Msg a = new DemoBuilderController.Msg();
        a.sender = 'them'; a.text = 'Hey'; a.sendAutomatically = true;
        DemoBuilderController.Msg b = new DemoBuilderController.Msg();
        b.sender = 'me'; b.awaitPhoto = true;
        DemoBuilderController.Msg r = new DemoBuilderController.Msg();
        r.sender = 'me'; r.text = 'Answering that'; r.replyToStep = 1;
        c.messages.add(a); c.messages.add(b); c.messages.add(r);
        t.conversations.add(c);

        DemoBuilderController.Notif n = new DemoBuilderController.Notif();
        n.title = 'Nora Bennett'; n.message = 'Send a photo?'; n.conversationKey = 'nora';
        n.documentIcon = 'https://example.com/thumb.png';
        n.callKey = 'nora'; n.afterSeconds = 6;
        t.notifications.add(n);

        DemoBuilderController.saveDemo(JSON.serialize(t));
        return demoId;
    }

    @IsTest
    static void savesAndReloadsTheWholeTree() {
        Test.startTest();
        String demoId = seed();
        Test.stopTest();

        DemoBuilderController.DemoTree back = DemoBuilderController.loadDemo(demoId);
        Assert.areEqual(1, back.conversations.size());
        Assert.areEqual(3, back.conversations[0].messages.size());
        Assert.areEqual(1, back.conversations[0].messages[2].replyToStep,
            'the quoted step must survive a round trip');
        Assert.areEqual(1, back.notifications.size());
        Assert.areEqual('https://example.com/thumb.png', back.notifications[0].documentIcon,
            'fields edited in the technical view must not disappear');
        Assert.areEqual('nora', back.notifications[0].callKey,
            'the call a banner belongs to must survive a round trip');
        Assert.areEqual(6, back.notifications[0].afterSeconds,
            'so must the second it drops in at');
        Assert.areEqual('Nora Bennett', back.conversations[0].contactName);
        Assert.isTrue(back.conversations[0].messages[1].awaitPhoto, 'the photo gate must survive a round trip');
    }

    @IsTest
    static void savingRenumbersFavoritesDenselyInTheOrderAsked() {
        String demoId = seed();
        DemoBuilderController.DemoTree t = DemoBuilderController.loadDemo(demoId);

        // Two more threads, one of them deliberately out of the Phone app, and a
        // Favorites order that does not match the Messages one.
        DemoBuilderController.Conversation quiet = new DemoBuilderController.Conversation();
        quiet.conversationKey = 'marcus';
        quiet.contactName = 'Marcus Hale';
        quiet.showInPhone = false;
        quiet.phoneSortOrder = 7;

        DemoBuilderController.Conversation goose = new DemoBuilderController.Conversation();
        goose.conversationKey = 'delivery';
        goose.contactName = 'Canada Goose';
        goose.showInPhone = true;
        goose.phoneSortOrder = 1;

        // Nora is first in Messages but asked for the second Favorites slot.
        t.conversations[0].phoneSortOrder = 4;
        t.conversations.add(quiet);
        t.conversations.add(goose);
        DemoBuilderController.saveDemo(JSON.serialize(t));

        DemoBuilderController.DemoTree back = DemoBuilderController.loadDemo(demoId);
        Map<String, Decimal> order = new Map<String, Decimal>();
        for (DemoBuilderController.Conversation c : back.conversations) {
            order.put(c.conversationKey, c.phoneSortOrder);
        }
        Assert.areEqual(1, order.get('delivery'), 'the requested order must be kept');
        Assert.areEqual(2, order.get('nora'), '4 and 1 must collapse to 2 and 1');
        Assert.isNull(order.get('marcus'),
            'a thread outside the Phone app must not hold a Favorites slot');
    }

    @IsTest
    static void theVoiceLineSurvivesARoundTripTrimmedAndCanBeCleared() {
        String demoId = seed();

        DemoBuilderController.DemoTree t = DemoBuilderController.loadDemo(demoId);
        t.conversations[0].voiceConnection = 'messaging';
        t.conversations[0].voiceMyDomain = ' https://acme.my.salesforce.com\n';
        t.conversations[0].voiceEsDeveloperName = 'ADA_Mobile ';
        t.conversations[0].voiceOrgId = '00D000000000001';
        t.conversations[0].voiceScrtUrl = 'https://acme.my.salesforce-scrt.com';
        DemoBuilderController.saveDemo(JSON.serialize(t));

        DemoBuilderController.DemoTree back = DemoBuilderController.loadDemo(demoId);
        Assert.areEqual('messaging', back.conversations[0].voiceConnection);
        Assert.areEqual('https://acme.my.salesforce.com', back.conversations[0].voiceMyDomain,
            'pasted credentials must be stored without the stray whitespace');
        Assert.areEqual('ADA_Mobile', back.conversations[0].voiceEsDeveloperName);

        // The combobox sends '' when cleared; the picklist is restricted.
        back.conversations[0].voiceConnection = '';
        back.conversations[0].voiceMyDomain = '';
        DemoBuilderController.saveDemo(JSON.serialize(back));

        DemoBuilderController.DemoTree cleared = DemoBuilderController.loadDemo(demoId);
        Assert.isNull(cleared.conversations[0].voiceConnection);
        Assert.isNull(cleared.conversations[0].voiceMyDomain);
    }

    @IsTest
    static void thePhoneContactSurvivesARoundTripAndCanBeClearedBackToBlank() {
        String demoId = seed();

        DemoBuilderController.DemoTree back = DemoBuilderController.loadDemo(demoId);
        Assert.isTrue(back.conversations[0].showInPhone, 'the Phone tick must survive a round trip');
        Assert.areEqual('iPhone', back.conversations[0].phoneLabel);
        Assert.areEqual(4, back.conversations[0].ringSeconds);
        Assert.areEqual(1, back.conversations[0].phoneSortOrder,
            'the only contact in the Phone app must be numbered 1');

        // The combobox sends '' when the pick is cleared, and Phone Label is a
        // restricted picklist that only accepts null — the case that would blow up.
        back.conversations[0].phoneLabel = '';
        back.conversations[0].showInPhone = false;
        DemoBuilderController.saveDemo(JSON.serialize(back));

        DemoBuilderController.DemoTree cleared = DemoBuilderController.loadDemo(demoId);
        Assert.isNull(cleared.conversations[0].phoneLabel);
        Assert.isFalse(cleared.conversations[0].showInPhone,
            'unticking it must keep the thread out of the Phone app');
        Assert.isNull(cleared.conversations[0].phoneSortOrder,
            'and it must give up its Favorites slot');
    }

    @IsTest
    static void theBubbleStyleSurvivesARoundTripAndClearsBackToBlank() {
        String demoId = seed();

        DemoBuilderController.DemoTree t = DemoBuilderController.loadDemo(demoId);
        Assert.isNull(t.demo.bubbleStyle, 'a new demo must not force a colour');

        t.demo.bubbleStyle = 'SMS';
        DemoBuilderController.saveDemo(JSON.serialize(t));
        Assert.areEqual('SMS', DemoBuilderController.loadDemo(demoId).demo.bubbleStyle);

        // The combobox sends '' for "Per conversation"; a restricted picklist
        // only accepts null, so this is the case that would blow up.
        t = DemoBuilderController.loadDemo(demoId);
        t.demo.bubbleStyle = '';
        DemoBuilderController.saveDemo(JSON.serialize(t));
        Assert.isNull(DemoBuilderController.loadDemo(demoId).demo.bubbleStyle,
            'clearing the picker must hand the colour back to the conversations');
    }

    @IsTest
    static void savingReplacesChildrenRatherThanAppending() {
        String demoId = seed();

        DemoBuilderController.DemoTree t = DemoBuilderController.loadDemo(demoId);
        String conversationId = t.conversations[0].id;
        String firstMessageId = t.conversations[0].messages[0].id;
        t.conversations[0].messages.remove(1);
        DemoBuilderController.saveDemo(JSON.serialize(t));

        DemoBuilderController.DemoTree back = DemoBuilderController.loadDemo(demoId);
        Assert.areEqual(2, back.conversations[0].messages.size(), 'removing a step must actually remove it');
        Assert.areEqual(conversationId, back.conversations[0].id,
            'saving must preserve the conversation identity');
        Assert.areEqual(firstMessageId, back.conversations[0].messages[0].id,
            'saving must preserve unchanged message identities');
    }

    @IsTest
    static void onlyOneDemoStaysActive() {
        String firstId = DemoBuilderController.createDemo('First');
        DemoBuilderController.DemoTree first = DemoBuilderController.loadDemo(firstId);
        first.demo.isActive = true;
        DemoBuilderController.saveDemo(JSON.serialize(first));

        String secondId = DemoBuilderController.createDemo('Second');
        DemoBuilderController.DemoTree second = DemoBuilderController.loadDemo(secondId);
        second.demo.isActive = true;
        DemoBuilderController.saveDemo(JSON.serialize(second));

        Assert.areEqual(1, [SELECT COUNT() FROM iMessage_Demo__c WHERE Is_Active__c = TRUE],
            'flagging one active must clear the others');
        Assert.areEqual(secondId, [SELECT Id FROM iMessage_Demo__c WHERE Is_Active__c = TRUE].Id);
    }

    @IsTest
    static void everyDemoGetsAStableNamedUrl() {
        String id = DemoBuilderController.createDemo('Named demo');
        DemoBuilderController.DemoTree t = DemoBuilderController.loadDemo(id);
        t.demo.configName = 'named demo';
        t.demo.isActive = true;
        DemoBuilderController.saveDemo(JSON.serialize(t));

        DemoBuilderController.DemoTree loaded = DemoBuilderController.loadDemo(id);
        String named = DemoBuilderController.endpointUrl('named demo', true);
        String inactiveNamed = DemoBuilderController.endpointUrl('named demo', false);
        if (named != null) {
            Assert.isTrue(
                named.contains('?id=named+demo') || named.contains('?id=named%20demo'),
                'every demo keeps a stable named URL: ' + named
            );
            Assert.areEqual(named, inactiveNamed, 'active flag must not change the demo URL');
            Assert.areEqual(named, loaded.endpointUrl, 'loadDemo should expose the stable URL');
            Assert.isNotNull(loaded.defaultUrl, 'loadDemo should expose the bare default URL');
            Assert.isFalse(loaded.defaultUrl.contains('?id='), 'default URL stays bare');
        }
    }

    @IsTest
    static void listsAndDeletes() {
        String id = seed();
        Assert.isFalse(DemoBuilderController.listDemos().isEmpty());
        DemoBuilderController.DemoTree current = DemoBuilderController.loadDemo(id);
        DemoBuilderController.deleteDemo(id, current.versionToken);
        Assert.areEqual(0, [SELECT COUNT() FROM iMessage_Demo__c WHERE Id = :id]);
    }

    @IsTest
    static void savesAdvisoryIssues() {
        String id = seed();
        DemoBuilderController.DemoTree t = DemoBuilderController.loadDemo(id);

        DemoBuilderController.Conversation duplicate = new DemoBuilderController.Conversation();
        duplicate.contactName = 'Duplicate';
        duplicate.conversationKey = 'NORA';
        DemoBuilderController.Msg secondPhotoGate = new DemoBuilderController.Msg();
        secondPhotoGate.sender = 'me';
        secondPhotoGate.awaitPhoto = true;
        duplicate.messages = new List<DemoBuilderController.Msg>{ secondPhotoGate };
        t.conversations.add(duplicate);

        DemoBuilderController.saveDemo(JSON.serialize(t));
        Assert.areEqual(2, [
            SELECT COUNT() FROM iMessage_Conversation__c WHERE Demo__c = :id
        ], 'warnings such as duplicate keys and multiple photo gates must not block saving');
    }

    @IsTest
    static void rejectsStaleBrowserState() {
        String id = seed();
        DemoBuilderController.DemoTree stale = DemoBuilderController.loadDemo(id);

        iMessage_Demo__c changed = [SELECT Id, Name FROM iMessage_Demo__c WHERE Id = :id];
        changed.Name = 'Changed elsewhere';
        update changed;

        assertSaveFails(stale, 'changed after you opened it');
    }

    @IsTest
    static void databaseStillProtectsDuplicateConfigNames() {
        String firstId = DemoBuilderController.createDemo('Original');
        String secondId = DemoBuilderController.createDemo('Copy');
        String firstConfig = [
            SELECT Config_Name__c FROM iMessage_Demo__c WHERE Id = :firstId
        ].Config_Name__c;

        DemoBuilderController.DemoTree second = DemoBuilderController.loadDemo(secondId);
        second.demo.configName = firstConfig;
        assertSaveFails(second, 'duplicate value');
    }

    @IsTest
    static void createsReadableUniqueConfigSlugs() {
        String firstId = DemoBuilderController.createDemo('Executive Support Call');
        String secondId = DemoBuilderController.createDemo('Executive Support Call');
        Set<Id> demoIds = new Set<Id>{ firstId, secondId };
        Map<Id, iMessage_Demo__c> demos = new Map<Id, iMessage_Demo__c>([
            SELECT Config_Name__c FROM iMessage_Demo__c WHERE Id IN :demoIds
        ]);

        Assert.areEqual('executive-support-call', demos.get(firstId).Config_Name__c);
        Assert.areEqual('executive-support-call-2', demos.get(secondId).Config_Name__c);
    }

    @IsTest
    static void duplicatesACompleteDemoWithNewRecordIds() {
        String sourceId = seed();
        DemoBuilderController.DemoTree source = DemoBuilderController.loadDemo(sourceId);

        String copyId = DemoBuilderController.cloneDemo(
            sourceId,
            source.versionToken,
            'Builder test copy'
        );
        DemoBuilderController.DemoTree copy = DemoBuilderController.loadDemo(copyId);

        Assert.areNotEqual(sourceId, copyId);
        Assert.areEqual(1, copy.conversations.size());
        Assert.areEqual(3, copy.conversations[0].messages.size());
        Assert.areNotEqual(source.conversations[0].id, copy.conversations[0].id);
        Assert.isFalse(copy.demo.isActive, 'a duplicate must not replace the active demo');
        Assert.areEqual('builder-test-copy', copy.demo.configName);
    }

    private static void assertSaveFails(
        DemoBuilderController.DemoTree tree,
        String expectedMessage
    ) {
        try {
            DemoBuilderController.saveDemo(JSON.serialize(tree));
            Assert.fail('Expected save to fail with: ' + expectedMessage);
        } catch (AuraHandledException error) {
            Assert.isTrue(
                error.getMessage().contains(expectedMessage),
                'Unexpected error: ' + error.getMessage()
            );
        }
    }
}