# #527 delete action identity from retained AX

Base: hosted e9cbfa8b283f5c31630186efe22411300ad16564,
tree 71a2515353b4f8f37454831823c15667cd8f4d96.
Journal run 43437389780, two real assertions at lines 297 and 343.

Both retained PNGs show exactly one native alert, one Cancel and one Delete.
Both full alert AX dumps show each action as a parent Button containing a child
Button with the same identifier, label and exact frame. Cancel is
(57,473,140,48); Delete is (205,473,140,48). The native app already adds exactly
one UIAlertAction for each decision. Another product presenter rewrite would
not be justified by this evidence. Earlier ab1e890/evidence-packet attempts
also showed raw count two; the new final-head AX finally identifies its shape.

The UI test now asserts one distinct terminal action, not one framework node:
- exactly one alert; named decision exists; no same-label action outside its ID;
- every matching node has the expected label and contains no different action;
- exactly one terminal button, not two sibling leaves (even if overlapping);
- every ancestor alias has the exact terminal frame and is enabled;
- nonempty terminal frame inside the alert, terminal action is hittable.

Only after uniqueness is proved does it tap that terminal element once. No
firstMatch, coordinate tap, >=1 acceptance, dedup by frame alone, hiding nodes,
retry, timeout or product mutation. All cancel-preserves-text, failed-delete
retains-detail/error, explicit user retry, successful dismissal and saved-history
removal assertions stay. Both Cancel and Delete are validated at all four alerts.
The existing native selected journeys still exercise the real delete behaviour.

Python suite and Swift grammar/diff checks pass. These are source checks, not
native acceptance. Updated simulator replay/AX and pixels remain required.
No production source changed, so existing build-focus pins are unchanged.
