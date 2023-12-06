//
//  Interactions.swift
//  Jumpcut
//
//  Created by Steve Cook on 2/5/22.
//

import Cocoa
import Sauce

public class Interactions: NSObject {
    /*
     * Responses to user actions, such as selecting a clipping via the
     * bezel or clicking "Clear All".
     */

    weak private var pasteboard: Pasteboard!
    weak private var stack: ClippingStack!
    weak private var menu: MenuManager!
    weak private var bezel: Bezel!
    weak private var delegate: AppDelegate!

    init(bezel: Bezel, menu: MenuManager, pasteboard: Pasteboard, stack: ClippingStack) {
        self.pasteboard = pasteboard
        self.stack = stack
        self.menu = menu
        self.bezel = bezel
        self.delegate = (NSApplication.shared.delegate as? AppDelegate)!
    }

    // HOTKEY
    func setHotkeyHandlers() {
        bezel.setMetaKeyReleaseHandler(handler: {
            if let sticky = UserDefaults.standard.value(forKey: SettingsPath.stickyBezel.rawValue) as? Bool {
                if !sticky {
                    self.bezelSelection()
                }
            }
        })
        bezel.setKeyDownHandler(handler: {(event: NSEvent) -> Void in
            // Note that the event.keyCode is locale-independent; it gives us
            // the ANSI-standard keycode, representing the QWERTY layout. To
            // handle things otherwise, we'll do a lookup in Sauce.
            if let key = SauceKey.init(QWERTYKeyCode: Int(event.keyCode)) {
                if key == self.delegate.hotKeyBase {
                    if event.modifierFlags.contains(.shift) {
                        self.stack.up()
                        self.displayBezelAtPosition(position: self.stack.position)
                    } else {
                        self.stack.down()
                        self.displayBezelAtPosition(position: self.stack.position)
                    }
                } else {
                    self.bezelKeyDownBehavior(key: key)
                }
            }
        })
    }

    // PASTEBOARD
    func place(_ clipping: Clipping) {
        // Place the clipping on the top of the pasteboard, then resign from
        // front.
        pasteboard.set(clipping.fullText)
        delegate.hide()
    }

    func paste(_ clipping: Clipping) {
        // Place the clipping on the top of the pasteboard, and 0.2 seconds
        // later, emit a Command-V event to paste.
        place(clipping)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.pasteboard.fakeCommandV()
        }
    }

    // BEZEL
    public func bezelSelection() {
        let clipping = stack.itemAt(position: stack.position)
        guard clipping != nil else {
            return
        }
        if bezel.shouldSelectionPaste() {
            paste(clipping!)
        } else {
            place(clipping!)
        }
        let moveToTop = UserDefaults.standard.value(
            forKey: SettingsPath.moveClippingsAfterUse.rawValue
        ) as? Bool ?? false
        if moveToTop {
            stack.moveItemToTop(position: stack.position)
            stack.position = 0
            menu.rebuild(stack: stack)
        }
    }

    private func handleBezelNumber(numberKey: SauceKey) {
        var number: Int?
        switch numberKey {
        case .one, .keypadOne:
            number = 1
        case .two, .keypadTwo:
            number = 2
        case .three, .keypadThree:
            number = 3
        case .four, .keypadFour:
            number = 4
        case .five, .keypadFive:
            number = 5
        case .six, .keypadSix:
            number = 6
        case .seven, .keypadSeven:
            number = 7
        case .eight, .keypadEight:
            number = 8
        case .nine, .keypadNine:
            number = 9
        case .zero, .keypadZero:
            number = 10
        default:
            break
        }
        guard number != nil else {
            return
        }
        guard self.stack.count > 0 else {
            return
        }
        if self.stack.count >= number! {
            self.stack.position = number! - 1
        } else {
            self.stack.position = self.stack.count - 1
        }
        displayBezelAtPosition(position: self.stack.position)
    }

    public func displayBezelAtPosition(position: Int) {
        guard !stack.isEmpty() else {
            return
        }
        // Note that our display is one-indexed, but the stack itself
        // is zero-indexed.
        var displayPos: Int
        var text: String
        var item = stack.itemAt(position: position)
        if item == nil {
            item = stack.itemAt(position: 0)
        }
        text = item!.fullText
        displayPos = position + 1
        bezel.setText(text: text)
        bezel.setSecondaryText(text: String(displayPos))
        if !bezel.shown {
            bezel.show()
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func moveAndDisplay(steps: Int) {
        guard stack.count > 0 else {
            return
        }
        self.stack.move(steps: steps)
        displayBezelAtPosition(position: self.stack.position)
    }

    func bezelKeyDownBehavior(key: SauceKey) {
        // Possible improvement: Use a lookup table instead of a switch statement
        // to enable adding behavior based on a preference.
        switch key {
        case .escape:
            delegate.hide()
        case .downArrow, .rightArrow:
            self.stack.down()
            displayBezelAtPosition(position: self.stack.position)
        case .pageDown:
            moveAndDisplay(steps: 10)
        case .home:
            handleBezelNumber(numberKey: .one)
        case .one, .two, .three, .four, .five, .six, .seven, .eight, .nine, .zero,
                .keypadOne, .keypadTwo, .keypadThree, .keypadFour, .keypadFive,
                .keypadSix, .keypadSeven, .keypadEight, .keypadNine, .keypadZero:
            handleBezelNumber(numberKey: key)
        case .end:
            if self.stack.count > 0 {
                self.stack.position = self.stack.count - 1
                displayBezelAtPosition(position: self.stack.position)
            }
        case .pageUp:
            moveAndDisplay(steps: -10)
        case .upArrow, .leftArrow:
            self.stack.up()
            displayBezelAtPosition(position: self.stack.position)
        case .return, .keypadEnter:
            bezelSelection()
        case .delete, .forwardDelete:
            self.stack.delete()
            self.menu.rebuild(stack: stack)
            if self.stack.isEmpty() {
                delegate.hide()
            } else {
                displayBezelAtPosition(position: self.stack.position)
            }
        default:
            break
        }
    }

    // MENU
    private func menuHandler(item: NSMenuItem!, wantsPaste: Bool) {
        let idx = extractIndex(menuItem: item)
        let clipping = stack.itemAt(position: idx)
        guard clipping != nil else {
            delegate.hide()
            return
        }
        if wantsPaste {
            paste(clipping!)
        } else {
            place(clipping!)
        }
        let moveToTop = UserDefaults.standard.value(
            forKey: SettingsPath.moveClippingsAfterUse.rawValue
        ) as? Bool ?? false
        if moveToTop {
            stack.moveItemToTop(position: idx)
            if idx == stack.position {
                stack.position = 0
            } else if idx > stack.position {
                stack.position += 1
            }
            menu.rebuild(stack: stack)
        }
    }

    @objc public func menuSelection(sender: NSMenuItem!) {
        menuHandler(item: sender, wantsPaste: menu.shouldSelectionPaste())
    }

    @objc public func menuPlace(sender: NSMenuItem!) {
        menuHandler(item: sender, wantsPaste: false)
    }

    @objc public func menuPaste(sender: NSMenuItem!) {
        menuHandler(item: sender, wantsPaste: true)
    }

    @objc public func menuDelete(sender: NSMenuItem!) {
        let idx = extractIndex(menuItem: sender)
        // stack.deleteAt() takes care of resetting the stack position.
        stack.deleteAt(position: idx)
        menu.rebuild(stack: stack)
    }

    private func extractIndex(menuItem: NSMenuItem!) -> Int {
        // Utility function to abstract over calling our menu-driven behaviors
        // for individual clippings from either the standard or the alternative
        // menu.
        var topLevel: NSMenu
        var item: NSMenuItem
        if menuItem.parent != nil {
            topLevel = menuItem.parent!.menu!
            item = menuItem.parent!
        } else {
            topLevel = menuItem.menu!
            item = menuItem
        }
        return topLevel.index(of: item)
    }

    private func _clearAll() {
        /*
         * If the top item in our stack is on the pasteboard, we also want
         * to clear the pasteboard itself. We don't care about the expense
         * of this, because clear all is an uncommon behavior, not in a
         * hot loop.
         */
        guard !stack.isEmpty() else {
            return
        }
        if let topOfPasteboard = pasteboard.topItem() {
            let topOfStack = stack.itemAt(position: 0)
            if topOfPasteboard == topOfStack!.fullText {
                pasteboard.set("", autogenerated: true)
            }
        }
        stack.clear()
        menu.rebuild(stack: stack)
    }

    @objc public func clearAll(sender: AnyObject?) {
        let ask = UserDefaults.standard.value(forKey: SettingsPath.askBeforeClearingClippings.rawValue) as? Bool ?? true
        if ask {
            let alert = Alerts.clearAllWarning()
            let response = alert.runModal()
            if response == .alertFirstButtonReturn && !stack.isEmpty() {
                _clearAll()
            }
            if let supress = alert.suppressionButton {
                if supress.state == NSControl.StateValue.on {
                    UserDefaults.standard.set(false, forKey: SettingsPath.askBeforeClearingClippings.rawValue)
                }
            }
        } else {
            _clearAll()
        }
    }
}
