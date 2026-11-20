"""Exact Group28 child-to-row gesture targeting correction."""
OLD='''        // leading swipe: favourite + add to list
        a.swipeRight()
        wait(app.buttons["Favourite"].firstMatch, 3)'''
NEW='''        // Target the full list row, not the narrow StaticText title child.
        // Native failure AX: title 128x23.7 inside the 402x100 listCard.
        let appleRow = app.buttons.matching(identifier: "listCard")
            .containing(.staticText, identifier: "Apple crumble")
        XCTAssertEqual(appleRow.count, 1, "Swipe must target the unique Apple crumble list row")
        appleRow.element(boundBy: 0).swipeRight()
        wait(app.buttons["Favourite"].firstMatch, 3)'''
def restore(path,raw):
    from ui_progress_stream_delta import restore as restore_progress
    raw = restore_progress(path,raw)
    from named_ui_red_rewrite_delta import restore as restore_reds
    raw = restore_reds(path,raw)
    if path.split(':',1)[-1]!='AteUITests/AteUITests.swift':return raw
    binary=isinstance(raw,bytes);text=raw.decode() if binary else raw
    if NEW not in text:
        assert text.count(OLD)==1
        return raw
    assert text.count(NEW)==1
    text=text.replace(NEW,OLD,1)
    return text.encode() if binary else text
