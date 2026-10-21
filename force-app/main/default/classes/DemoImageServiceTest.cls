@IsTest
private class DemoImageServiceTest {

    private static String tinyPng() {
        // A 1x1 PNG, enough to prove the round trip without carrying a fixture.
        return 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
    }

    @IsTest
    static void uploadingReturnsAPublicUrl() {
        Test.startTest();
        DemoImageService.UploadResult r = DemoImageService.uploadImage(tinyPng(), 'poster.png');
        Test.stopTest();

        Assert.isNotNull(r.url, 'a distribution must produce a download URL');
        Assert.areEqual('poster.png', r.fileName);
        Assert.isTrue(r.bytes > 0);
        Assert.areEqual(1, [SELECT COUNT() FROM ContentDistribution WHERE Name = 'poster.png']);
    }

    @IsTest
    static void blankFileIsRejected() {
        try {
            DemoImageService.uploadImage('', 'x.png');
            Assert.fail('expected a rejection');
        } catch (Exception e) {
            Assert.isInstanceOfType(e, AuraHandledException.class);
        }
    }

    @IsTest
    static void aMissingNameFallsBack() {
        DemoImageService.UploadResult r = DemoImageService.uploadImage(tinyPng(), null);
        Assert.areEqual('demo-image.png', r.fileName);
    }
}
