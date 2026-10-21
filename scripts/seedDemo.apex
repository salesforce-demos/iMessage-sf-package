// Generated from the app's Configs.json — edit there and regenerate, or edit in the Builder.
// Re-runnable: it clears the matching demo first.

String configName = 'Salesforce — call, notification, photo reply';
// Reuse the active demo's record when there is one, so a Builder tab someone
// left open keeps pointing at something real. Only the children get replaced.
List<iMessage_Demo__c> existing = [SELECT Id FROM iMessage_Demo__c WHERE Is_Active__c = TRUE LIMIT 1];
Id keepId = existing.isEmpty() ? null : existing[0].Id;
delete [SELECT Id FROM iMessage_Demo__c WHERE Config_Name__c = :configName AND Id != :keepId];
// Only one demo may be active, or the endpoint and the Builder can disagree
// about which one they are looking at.
List<iMessage_Demo__c> others = [SELECT Id FROM iMessage_Demo__c WHERE Is_Active__c = TRUE AND Id != :keepId];
for (iMessage_Demo__c o : others) { o.Is_Active__c = false; }
if (!others.isEmpty()) { update others; }

iMessage_Demo__c demo = new iMessage_Demo__c(
    Id = keepId,
    Name = 'Salesforce support call', Config_Name__c = configName, Is_Active__c = true,
    SB_Carrier__c = 'T-Mobile', SB_Signal_Bars__c = 4,
    SB_WiFi_Strength__c = 3, SB_Show_WiFi__c = true,
    SB_Battery_Level__c = 0.82, SB_Is_Charging__c = false
);
upsert demo;
delete [SELECT Id FROM iMessage_Notification__c WHERE Demo__c = :demo.Id];
delete [SELECT Id FROM iMessage_Conversation__c WHERE Demo__c = :demo.Id];

// Every banner names the call it drops into and the second it drops in at,
// counted from the moment that call connects.
List<iMessage_Notification__c> notifs = new List<iMessage_Notification__c>();
notifs.add(new iMessage_Notification__c(
    Name = 'Salesforce', Demo__c = demo.Id, Sort_Order__c = 1,
    Icon_Name__c = 'message.fill',
    Icon_Color__c = '#4CD964', Title__c = 'Salesforce',
    Message__c = 'Can you send a photo of the unit? I\'ll attach it to case #00123.', Time_Ago__c = 'now',
    Conversation_Key__c = 'salesforce', Call_Key__c = 'salesforce', After_Seconds__c = 6
));
notifs.add(new iMessage_Notification__c(
    Name = 'Canada Goose', Demo__c = demo.Id, Sort_Order__c = 2,
    Icon_Name__c = 'message.fill',
    Icon_Color__c = '#4CD964', Title__c = 'Canada Goose',
    Message__c = 'Your package was delivered to the front door.', Time_Ago__c = 'now',
    Conversation_Key__c = 'delivery', Call_Key__c = 'delivery', After_Seconds__c = 5
));
// Two on one call, to show a sequence: the second lands once the first is gone.
notifs.add(new iMessage_Notification__c(
    Name = 'Blink badge', Demo__c = demo.Id, Sort_Order__c = 3,
    Icon_Name__c = 'message.fill',
    Icon_Color__c = '#4CD964', Title__c = 'Blink',
    Message__c = 'You earned the Agentforce Basics badge 🎉', Time_Ago__c = 'now',
    Conversation_Key__c = 'trailhead', Call_Key__c = 'trailhead', After_Seconds__c = 5
));
notifs.add(new iMessage_Notification__c(
    Name = 'Blink motion', Demo__c = demo.Id, Sort_Order__c = 4,
    Icon_Name__c = 'bell.fill',
    Icon_Color__c = '#FF9500', Title__c = 'Blink',
    Message__c = 'Front door camera detected motion.', Time_Ago__c = 'now',
    Conversation_Key__c = 'trailhead', Call_Key__c = 'trailhead', After_Seconds__c = 16
));
insert notifs;

// Each conversation is also its own Phone contact. Phone_Sort_Order__c is the
// Favorites running order, which is not the Messages one.
List<iMessage_Conversation__c> convs = new List<iMessage_Conversation__c>();
convs.add(new iMessage_Conversation__c(
    Name = 'Salesforce', Demo__c = demo.Id, Sort_Order__c = 1,
    Conversation_Key__c = 'salesforce', Contact_Name__c = 'Salesforce',
    Contact_Subtitle__c = 'Customer Support', Avatar_URL__c = 'https://raw.githubusercontent.com/salesforce-demos/iMessage-sf-package/main/assets/seed/avatar-salesforce.png',
    Last_Message_Preview__c = 'Can you send a photo of the unit? I\'ll attach it to case #00123.',
    Last_Message_Time__c = 'now',
    Unread_Count__c = 2, Is_SMS__c = false,
    Is_Muted__c = false, Is_Forwarded__c = false,
    Transcript_Speed__c = 600, Draft_Text__c = null,
    Show_In_Phone__c = true, Phone_Sort_Order__c = 1,
    Phone_Label__c = 'mobile', Call_Subtitle__c = 'calling mobile…',
    Call_Background_URL__c = 'https://raw.githubusercontent.com/salesforce-demos/iMessage-sf-package/main/assets/seed/call-background-salesforce.png',
    Ring_Seconds__c = 4,
    // The banner carries its own `After Seconds`, so nothing is needed here.
    Notification_After_Seconds__c = null,
    // iOS-NativePhoneAgent: ADA answers this call. The plain app ignores it.
    Agent_Connection__c = 'agentAPI',
    Agent_My_Domain__c = 'https://acme.my.salesforce.com',
    Agent_Id__c = '0Xx000000000000000',
    Agent_Greeting__c = 'Hi, this is Salesforce Support. How can I help you today?'
));
convs.add(new iMessage_Conversation__c(
    Name = 'Blink', Demo__c = demo.Id, Sort_Order__c = 2,
    Conversation_Key__c = 'trailhead', Contact_Name__c = 'Blink',
    Contact_Subtitle__c = null, Avatar_URL__c = 'https://raw.githubusercontent.com/salesforce-demos/iMessage-sf-package/main/assets/seed/app-icon.jpg',
    Last_Message_Preview__c = 'You earned the Agentforce Basics badge 🎉',
    Last_Message_Time__c = '9:12 AM',
    Unread_Count__c = 0, Is_SMS__c = false,
    Is_Muted__c = true, Is_Forwarded__c = false,
    Transcript_Speed__c = 600, Draft_Text__c = null,
    Show_In_Phone__c = true, Phone_Sort_Order__c = 3,
    Phone_Label__c = 'mobile', Call_Subtitle__c = 'calling mobile…',
    Call_Background_URL__c = 'https://raw.githubusercontent.com/salesforce-demos/iMessage-sf-package/main/assets/seed/photo-door.webp',
    Ring_Seconds__c = 3,
    Notification_After_Seconds__c = null
));
convs.add(new iMessage_Conversation__c(
    Name = 'Marcus Hale', Demo__c = demo.Id, Sort_Order__c = 3,
    Conversation_Key__c = 'marcus', Contact_Name__c = 'Marcus Hale',
    Contact_Subtitle__c = null, Avatar_URL__c = null,
    Last_Message_Preview__c = 'Sounds good — see you at 3.',
    Last_Message_Time__c = 'Yesterday',
    Unread_Count__c = 0, Is_SMS__c = false,
    Is_Muted__c = false, Is_Forwarded__c = true,
    Transcript_Speed__c = 600, Draft_Text__c = null,
    Show_In_Phone__c = false
));
convs.add(new iMessage_Conversation__c(
    Name = 'Canada Goose', Demo__c = demo.Id, Sort_Order__c = 4,
    Conversation_Key__c = 'delivery', Contact_Name__c = 'Canada Goose',
    Contact_Subtitle__c = null, Avatar_URL__c = 'https://raw.githubusercontent.com/salesforce-demos/iMessage-sf-package/main/assets/seed/canada-goose-logo.png',
    Last_Message_Preview__c = 'Your package was delivered to the front door.',
    Last_Message_Time__c = 'Yesterday',
    Unread_Count__c = 0, Is_SMS__c = true,
    Is_Muted__c = false, Is_Forwarded__c = true,
    Transcript_Speed__c = 600, Draft_Text__c = null,
    Show_In_Phone__c = true, Phone_Sort_Order__c = 2,
    Phone_Label__c = 'mobile', Call_Subtitle__c = 'calling mobile…',
    Call_Background_URL__c = 'https://raw.githubusercontent.com/salesforce-demos/iMessage-sf-package/main/assets/seed/contact-background.png',
    Ring_Seconds__c = 3,
    Notification_After_Seconds__c = null
));
insert convs;

Map<String, Id> byKey = new Map<String, Id>();
for (iMessage_Conversation__c cv : convs) { byKey.put(cv.Conversation_Key__c, cv.Id); }
List<iMessage_Message__c> msgs = new List<iMessage_Message__c>();
msgs.add(new iMessage_Message__c(
    Name = 'Hi — Salesforce Support here, following up on case #00123.', Conversation__c = byKey.get('salesforce'), Sort_Order__c = 1,
    Sender__c = 'them', Text__c = 'Hi — Salesforce Support here, following up on case #00123.',
    Image_URL__c = null,
    Send_Automatically__c = true,
    Typing_Seconds__c = 1.4, Pause_Seconds__c = null,
    Delivery_Status__c = null, Tapback__c = null,
    Effect__c = null, Await_Photo__c = false,
    React_To_Previous__c = null,
    Reply_To_Step__c = null
));
msgs.add(new iMessage_Message__c(
    Name = 'Can you send a photo of the unit? I\'ll attach it to the case.', Conversation__c = byKey.get('salesforce'), Sort_Order__c = 2,
    Sender__c = 'them', Text__c = 'Can you send a photo of the unit? I\'ll attach it to the case.',
    Image_URL__c = null,
    Send_Automatically__c = true,
    Typing_Seconds__c = 1.8, Pause_Seconds__c = 0.4,
    Delivery_Status__c = null, Tapback__c = null,
    Effect__c = null, Await_Photo__c = false,
    React_To_Previous__c = null,
    Reply_To_Step__c = null
));
msgs.add(new iMessage_Message__c(
    Name = 'awaits photo', Conversation__c = byKey.get('salesforce'), Sort_Order__c = 3,
    Sender__c = 'me', Text__c = null,
    Image_URL__c = null,
    Send_Automatically__c = true,
    Typing_Seconds__c = null, Pause_Seconds__c = null,
    Delivery_Status__c = null, Tapback__c = null,
    Effect__c = null, Await_Photo__c = true,
    React_To_Previous__c = null,
    Reply_To_Step__c = null
));
msgs.add(new iMessage_Message__c(
    Name = 'reacts heart', Conversation__c = byKey.get('salesforce'), Sort_Order__c = 4,
    Sender__c = 'them', Text__c = null,
    Image_URL__c = null,
    Send_Automatically__c = true,
    Typing_Seconds__c = null, Pause_Seconds__c = 0.8,
    Delivery_Status__c = null, Tapback__c = null,
    Effect__c = null, Await_Photo__c = false,
    React_To_Previous__c = 'heart',
    Reply_To_Step__c = null
));
msgs.add(new iMessage_Message__c(
    Name = 'Perfect, that\'s exactly what we needed.', Conversation__c = byKey.get('salesforce'), Sort_Order__c = 5,
    Sender__c = 'them', Text__c = 'Perfect, that\'s exactly what we needed.',
    Image_URL__c = null,
    Send_Automatically__c = true,
    Typing_Seconds__c = 1.4, Pause_Seconds__c = 0.5,
    Delivery_Status__c = null, Tapback__c = null,
    Effect__c = null, Await_Photo__c = false,
    React_To_Previous__c = null,
    Reply_To_Step__c = null
));
msgs.add(new iMessage_Message__c(
    Name = 'Attached to case #00123 — an engineer picks it up within the hour.', Conversation__c = byKey.get('salesforce'), Sort_Order__c = 6,
    Sender__c = 'them', Text__c = 'Attached to case #00123 — an engineer picks it up within the hour.',
    Image_URL__c = null,
    Send_Automatically__c = true,
    Typing_Seconds__c = 2.1, Pause_Seconds__c = 0.4,
    Delivery_Status__c = null, Tapback__c = null,
    Effect__c = null, Await_Photo__c = false,
    React_To_Previous__c = null,
    Reply_To_Step__c = null
));
msgs.add(new iMessage_Message__c(
    Name = 'Anything else I can help with today?', Conversation__c = byKey.get('salesforce'), Sort_Order__c = 7,
    Sender__c = 'them', Text__c = 'Anything else I can help with today?',
    Image_URL__c = null,
    Send_Automatically__c = true,
    Typing_Seconds__c = 1.2, Pause_Seconds__c = 0.6,
    Delivery_Status__c = null, Tapback__c = null,
    Effect__c = null, Await_Photo__c = false,
    React_To_Previous__c = null,
    Reply_To_Step__c = null
));
msgs.add(new iMessage_Message__c(
    Name = 'You earned the Agentforce Basics badge 🎉', Conversation__c = byKey.get('trailhead'), Sort_Order__c = 1,
    Sender__c = 'them', Text__c = 'You earned the Agentforce Basics badge 🎉',
    Image_URL__c = null,
    Send_Automatically__c = true,
    Typing_Seconds__c = 1, Pause_Seconds__c = null,
    Delivery_Status__c = null, Tapback__c = null,
    Effect__c = 'slam', Await_Photo__c = false,
    React_To_Previous__c = null,
    Reply_To_Step__c = null
));
msgs.add(new iMessage_Message__c(
    Name = 'Are we still on for this afternoon?', Conversation__c = byKey.get('marcus'), Sort_Order__c = 1,
    Sender__c = 'them', Text__c = 'Are we still on for this afternoon?',
    Image_URL__c = null,
    Send_Automatically__c = true,
    Typing_Seconds__c = 1, Pause_Seconds__c = null,
    Delivery_Status__c = null, Tapback__c = null,
    Effect__c = null, Await_Photo__c = false,
    React_To_Previous__c = null,
    Reply_To_Step__c = null
));
msgs.add(new iMessage_Message__c(
    Name = 'Yep, 3pm works.', Conversation__c = byKey.get('marcus'), Sort_Order__c = 2,
    Sender__c = 'me', Text__c = 'Yep, 3pm works.',
    Image_URL__c = null,
    Send_Automatically__c = false,
    Typing_Seconds__c = null, Pause_Seconds__c = null,
    Delivery_Status__c = null, Tapback__c = null,
    Effect__c = null, Await_Photo__c = false,
    React_To_Previous__c = null,
    Reply_To_Step__c = null
));
msgs.add(new iMessage_Message__c(
    Name = 'Sounds good — see you at 3.', Conversation__c = byKey.get('marcus'), Sort_Order__c = 3,
    Sender__c = 'them', Text__c = 'Sounds good — see you at 3.',
    Image_URL__c = null,
    Send_Automatically__c = true,
    Typing_Seconds__c = 1.1, Pause_Seconds__c = null,
    Delivery_Status__c = null, Tapback__c = null,
    Effect__c = null, Await_Photo__c = false,
    React_To_Previous__c = null,
    Reply_To_Step__c = null
));
msgs.add(new iMessage_Message__c(
    Name = 'Your package was delivered to the front door.', Conversation__c = byKey.get('delivery'), Sort_Order__c = 1,
    Sender__c = 'them', Text__c = 'Your package was delivered to the front door.',
    Image_URL__c = null,
    Send_Automatically__c = true,
    Typing_Seconds__c = 1, Pause_Seconds__c = null,
    Delivery_Status__c = null, Tapback__c = null,
    Effect__c = null, Await_Photo__c = false,
    React_To_Previous__c = null,
    Reply_To_Step__c = null
));
insert msgs;
