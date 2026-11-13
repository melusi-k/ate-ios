# #527 option 2: fold delete repair, no waiver, fresh CI required

Packet base527:5725a43bee94a5a57e36869c8ab113827a9d266a.
Reuses actual hosted native-owner runtime5722cae39f3fbf6b2ed1f5bf2a7ea2cb30167a56,
whose complete tree equals prior reviewed lifecycle revisionf515ab2. No new
selector workaround: strict CRUD/delete-retry UI methods remain byte-identical.

## Compared failures

https://github.com/melusi-k/ate-ios/actions/runs/43372485083
#527 strict cancel line286 and confirm330 counted2 rather than1 on5725a43.
https://github.com/melusi-k/ate-ios/actions/runs/43395015519
#526 sparse AX tree shows Button->Button with the same delete.confirm identity;
Cancel similarly fails multiple-match lookup. This supports projection mismatch,
not two visible dialogs or a justified firstMatch/uniqueness waiver.

Native owner retains one alert and two native UIAlertActions, unique identifiers,
operation token through dismissal, and revocation on false/cancel/detach/retire.
Existing isolated committed delete/storage/edit-failure behavior unchanged.
Seven native alert/lifecycle methods added to strict required union38->45 with
all38 previous names retained. They are still UNRUN here. Static tests updated
to check concrete native owner and exact two actions; strict UI count1 retained.

https://github.com/melusi-k/ate-ios/actions/runs/43372485090
Compile account-cooking job131711382508 fails BottomBarsDoNotOverlapRecipeDetail
at3min. Tail reaches Exit132.30s, synthesize132.65s, idle wait132.96s then no app
idle notification193.01s. It does not reach bottom-bar overlap assertions. No
source-grounded Cook geometry fix can be inferred. Cook/test/timeouts unchanged;
this run remains red, and its exact-head successor must pass. No waiver, rerun,
relaxation, speculative Cook mutation or new paid capacity in this packet.

## Guards and qualification

Build focus pins actual hosted5722cae ancestor and all six runtime blobs, retaining
Cook/App/reflection evidence and adding native alert. Unchanged guard still fails
stale blobs/non-ancestors. No guard or workflow mutation. Python/static/grammar are
not native UI proof. Native build/typecheck/warnings, seven native unit methods,
strict cancel/delete/failure/explicit retry UI, actual alert pixels and fresh
Compile bottom-bars remain required, UNVERIFIED. Reviewer owns publishing and
fresh CI coordination. Source PRs close only after destination commit confirmed;
branches kept. Food Journal OFF. No issue closure, merge or production activation.
