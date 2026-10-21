/**
 * Takes an image straight from the builder and hands back a URL the phone can
 * fetch without a Salesforce session.
 *
 * Files plus a ContentDistribution is the supported way to do that: the
 * distribution's ContentDownloadUrl serves the raw bytes to anyone with the
 * link, which is exactly what both the app and the preview need.
 */
public with sharing class DemoImageService {

    /** Base64 grows the payload by a third, and Apex heap is 6MB. */
    private static final Integer MAX_BYTES = 3 * 1024 * 1024;

    public class UploadResult {
        @AuraEnabled public String url;
        @AuraEnabled public String fileName;
        @AuraEnabled public Integer bytes;
    }

    @AuraEnabled
    public static UploadResult uploadImage(String base64, String fileName) {
        if (String.isBlank(base64)) {
            throw new AuraHandledException('No file was sent.');
        }

        Blob body;
        try {
            body = EncodingUtil.base64Decode(base64);
        } catch (Exception e) {
            throw new AuraHandledException('That file could not be read.');
        }
        if (body.size() > MAX_BYTES) {
            throw new AuraHandledException(
                'That image is ' + (body.size() / 1024 / 1024) + 'MB. Keep it under 3MB.'
            );
        }

        String safeName = String.isBlank(fileName) ? 'demo-image.png' : fileName;

        ContentVersion cv = new ContentVersion(
            Title = safeName,
            PathOnClient = safeName,
            VersionData = body,
            IsMajorVersion = true
        );
        insert cv;

        // ContentDocumentId is only populated after the version is saved.
        cv = [SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id LIMIT 1];

        ContentDistribution dist = new ContentDistribution(
            Name = safeName,
            ContentVersionId = cv.Id,
            PreferencesAllowViewInBrowser = true,
            PreferencesAllowOriginalDownload = true,
            PreferencesNotifyOnVisit = false,
            PreferencesPasswordRequired = false,
            PreferencesExpires = false
        );
        insert dist;

        dist = [SELECT ContentDownloadUrl FROM ContentDistribution WHERE Id = :dist.Id LIMIT 1];

        UploadResult r = new UploadResult();
        r.url = dist.ContentDownloadUrl;
        r.fileName = safeName;
        r.bytes = body.size();
        return r;
    }
}
