// The site's guest user is created with the site; grant it the read-only set.
List<User> guests = [
    SELECT Id, Name, Username, Profile.Name
    FROM User
    WHERE UserType = 'Guest' AND IsActive = true
];
for (User u : guests) { System.debug(LoggingLevel.ERROR, '@@GUEST ' + u.Id + ' | ' + u.Name + ' | ' + u.Profile.Name); }

PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'iMessage_Demo_Guest' LIMIT 1];
List<PermissionSetAssignment> toAdd = new List<PermissionSetAssignment>();
Set<Id> already = new Set<Id>();
for (PermissionSetAssignment a : [SELECT AssigneeId FROM PermissionSetAssignment WHERE PermissionSetId = :ps.Id]) {
    already.add(a.AssigneeId);
}
for (User u : guests) {
    if (!already.contains(u.Id)) { toAdd.add(new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id)); }
}
if (!toAdd.isEmpty()) {
    List<Database.SaveResult> rs = Database.insert(toAdd, false);
    for (Integer i = 0; i < rs.size(); i++) {
        System.debug(LoggingLevel.ERROR, '@@ASSIGN ' + (rs[i].isSuccess() ? 'ok' : String.valueOf(rs[i].getErrors())));
    }
} else {
    System.debug(LoggingLevel.ERROR, '@@ASSIGN nothing to do');
}
