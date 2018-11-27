# rm2jira
moves redmine tickets to jira

`bin/cli migrate_tickets 'Walmart Content'`

if you see this error: `+[__NSPlaceholderDictionary initialize] may have been in progress in another thread when fork() was called.`
Run this before the command `export OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES`
