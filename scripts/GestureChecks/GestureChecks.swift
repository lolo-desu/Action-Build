import XCTest

final class GestureChecks: XCTestCase {
    let app=XCUIApplication(bundleIdentifier:"local.erp.stable")
    override func setUpWithError() throws {
        continueAfterFailure=false
        app.launchArguments=["--verify-gestures"]
        app.launch()
        let chat=app.links["虚构会话"]
        XCTAssertTrue(chat.waitForExistence(timeout:15));chat.tap()
        openProfile()
    }
    func openProfile() {
        let link=app.links["打开资料"]
        XCTAssertTrue(link.waitForExistence(timeout:5));link.tap()
        XCTAssertTrue(app.staticTexts["资料已就绪"].waitForExistence(timeout:8))
    }
    func backFromPhoto() {
        let photo=app.buttons["资料照片"]
        XCTAssertTrue(photo.waitForExistence(timeout:3))
        photo.coordinate(withNormalizedOffset:CGVector(dx:0.12,dy:0.5)).press(forDuration:0.05,thenDragTo:photo.coordinate(withNormalizedOffset:CGVector(dx:0.95,dy:0.5)),withVelocity:.slow,thenHoldForDuration:0)
        XCTAssertTrue(app.staticTexts["聊天页面"].waitForExistence(timeout:5))
    }
    func testPhotoTapAndRightSwipeAfterLayout() {
        app.buttons["资料照片"].tap()
        XCTAssertTrue(app.staticTexts["照片点击 1"].waitForExistence(timeout:3))
        backFromPhoto()
        openProfile();backFromPhoto()
    }
    func testSlowVerticalScrollFromPhoto() {
        let photo=app.buttons["资料照片"]
        photo.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.88)).press(forDuration:0.05,thenDragTo:photo.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.12)),withVelocity:.slow,thenHoldForDuration:0)
        let status=app.staticTexts.matching(NSPredicate(format:"label BEGINSWITH %@","页面滚动 ")).firstMatch
        let moved=NSPredicate { _,_ in status.exists && status.label != "页面滚动 0" }
        expectation(for:moved,evaluatedWith:status);waitForExpectations(timeout:4)
        XCTAssertTrue(app.staticTexts["个人资料"].exists,"Vertical scroll unexpectedly returned")
        app.webViews.firstMatch.swipeUp()
        XCTAssertTrue(app.staticTexts["资料最后一段"].exists)
    }
    func testHorizontalAlbumKeepsItsGesture() {
        let album=app.staticTexts["相册 A"]
        album.coordinate(withNormalizedOffset:CGVector(dx:0.85,dy:0.5)).press(forDuration:0.05,thenDragTo:album.coordinate(withNormalizedOffset:CGVector(dx:0.1,dy:0.5)),withVelocity:.slow,thenHoldForDuration:0)
        let status=app.staticTexts.matching(NSPredicate(format:"label BEGINSWITH %@","相册位置 ")).firstMatch
        let moved=NSPredicate { _,_ in status.exists && status.label != "相册位置 0" }
        expectation(for:moved,evaluatedWith:status);waitForExpectations(timeout:4)
        XCTAssertTrue(app.staticTexts["个人资料"].exists)
        backFromPhoto()
    }
    func testStalledSnapshotCannotFreezeReturnedPage() {
        app.buttons["冻结截图测试"].tap();backFromPhoto()
        let photoReturn=app.links["打开资料"]
        XCTAssertTrue(photoReturn.isHittable,"Parent stayed covered after dropped snapshot callback")
        openProfile()
        let photo=app.buttons["资料照片"]
        photo.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.8)).press(forDuration:0.05,thenDragTo:photo.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.2)),withVelocity:.slow,thenHoldForDuration:0)
        let status=app.staticTexts.matching(NSPredicate(format:"label BEGINSWITH %@","页面滚动 ")).firstMatch
        expectation(for:NSPredicate { _,_ in status.exists && status.label != "页面滚动 0" },evaluatedWith:status)
        waitForExpectations(timeout:4)
    }
}
