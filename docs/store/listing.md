# App Store listing

Copy for App Store Connect, plus the answers that submission asks for.

## Name

Kerbside

## Subtitle (30 characters)

`Where you parked, and until when` is 32. Use:

    Where you parked, and till when

## Promotional text (170)

    Save where you left the car, read the sign above it, and see what it says
    on your Lock Screen. Everything happens on your iPhone. No account, no
    server, no network.

## Description

    Kerbside remembers where you left the car, what the sign above it said, and
    how long that leaves you.

    Park, and it saves the spot. Photograph the sign, and it reads the panels
    on device and tells you what each one says: which rule is in force now,
    what changes next, and when.

    WHAT IT DOES

    • Saves where the car is and points you back to it with a bearing and a
      distance, working entirely offline
    • Reads NSW parking signs on the device — time limits, days, hours, arrows
    • Counts down the limit you chose, on the Lock Screen, in the Dynamic
      Island and in widgets
    • Reminds you before the limit runs out, and before a restriction starts
      applying — the 6am clearway you would not have thought about
    • Keeps a short list of where you have been, which you can delete

    WHAT IT DOES NOT DO

    Kerbside never tells you whether you may park. It has no green tick and no
    verdict. It shows what the sign says and names where every number came
    from, and the sign on the street remains the only authority.

    A panel it cannot read is shown as unread, as plainly as the ones it could.
    It is never guessed at.

    ON YOUR DEVICE

    No account. No server. No analytics. No network requests at all — the app
    works in airplane mode. Your location and your photographs stay on your
    iPhone.

    Kerbside reads New South Wales parking signs.

## Keywords (100)

    parking,sign,car,park,find my car,timer,reminder,kerb,curb,nsw,sydney,meter,offline

## Category

Primary: Navigation
Secondary: Utilities

## Age rating

4+

## Privacy nutrition label

Answer **"No, we do not collect data from this app."**

Every question that follows is skipped. Nothing is collected, because nothing
leaves the device — this is enforced by a test that scans the sources for
networking (`InvariantTests.noNetwork`).

## Review notes

Paste into App Review Information → Notes:

    Kerbside is a parking notebook for New South Wales, Australia.

    HOW TO TEST WITHOUT A PARKING SIGN
    Tap "Park here" on the first screen. This saves a spot using the device
    location and shows the main screen. Tap "Set a limit" to start a countdown.
    Tap "I'm back at the car" to end it. No sign photograph is needed to
    exercise the whole app.

    Sign reading is optional and only recognises Australian (NSW) parking
    plates. Photographing any other sign will correctly report that the panel
    could not be read; this is the designed behaviour, not a failure.

    ABOUT ACCURACY
    The app deliberately gives no parking verdict. It never states whether
    parking is permitted. It displays what the photographed sign says, which
    rule is in force at the current time, and a countdown against a limit the
    user explicitly selects. Every countdown names its source on screen ("The
    2 hour parking on this sign runs out at 3:00 pm" or "The 15 minute limit
    you set runs out at ..."). A first-run screen states that the sign on the
    street is the only authority.

    PERMISSIONS
    Location (when in use) is used only to record where the car was left and to
    compute distance and bearing back to it, on device. Notifications are
    requested only when the user turns reminders on. The app makes no network
    requests and functions in airplane mode.

## Privacy policy URL

Host `docs/store/privacy-policy.md` as a page and put the URL here. A GitHub
Pages site or a gist rendered page is enough.

## Export compliance

Uses no encryption beyond what Apple provides. Answer "No" to the encryption
question, or set `ITSAppUsesNonExemptEncryption` to `false`.
