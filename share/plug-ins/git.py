"""
Provides support for the Git configuration management system.

It integrates into GPS's VCS support, and uses the same menus
as all other VCS systems supported by GPS.
You can easily edit this file if you would like to customize
the git commands that are sent for each of the menus.

IMPORTANT NOTE1: Git is quite different from CVS and Subversion
for example. Not all GPS VCS commands are implemented at the
moment because they won't integrate nicely or most of the power
will be lost. For example interactive add or rebase commands
can't be integrated into GPS.
"""

###########################################################################
# No user customization below this line
###########################################################################

import GPS
import os.path
from gps_utils import interactive
from vcs import *


def from_git_root(filename):
    "Given a filename it returns the pathname relative to the Git root"
    dir = os.getcwd()
    full = ""
    while not os.path.exists(dir + '/.git'):
        full = os.path.basename(dir) + "/" + full
        dir = os.path.dirname(dir)
    full = full + filename
    return full

#  Git VCS Menu

actions = [

    SEPARATOR,

    {ACTION: "Status", LABEL: "Query _status"},
    {ACTION: "Commit", LABEL: "_Commit"},
    {ACTION: "Commit (via revision log)",
     LABEL: "_Commit (via revision log)"},
    {ACTION: "Commit (from revision log)", LABEL: "Commit file"},

    SEPARATOR,

    {ACTION: "History (as text)",
        LABEL: "View _entire revision history (as text)"},
    {ACTION: "History",
     LABEL: "View _entire revision history"},
    {ACTION: "History for revision",
     LABEL: "View specific revision _history"},

    SEPARATOR,

    {ACTION: "Diff against head",
     LABEL: "Compare against head revision"},

    SEPARATOR,

    {ACTION: "Annotate",                LABEL: "Add annotations"},
    {ACTION: "Remove Annotate",         LABEL: "Remove annotations"},
    {ACTION: "Edit revision log",       LABEL: "Edit revision log"},
    {ACTION: "Edit global ChangeLog",   LABEL: "Edit global ChangeLog"},
    {ACTION: "Remove revision log",     LABEL: "Remove revision log"},

    SEPARATOR,

    {ACTION: "Add no commit",             LABEL: "Add, no commit"},

    {ACTION: "View revision", LABEL: "View revision"},

    SEPARATOR,

    {ACTION: "Status dir",
     LABEL: "Directory/Query status for directory"},
    {ACTION: "Status dir (recursively)",     LABEL:
        "Directory/Query status for directory recursively"},
    {ACTION: "Update dir (recursively)",
        LABEL: "Directory/Update directory recursively"},

    {ACTION: "List project",
     LABEL: "Project/List all files in project"},
    {ACTION: "Status project",
     LABEL: "Project/Query status for project"},
    {ACTION: "Update project",               LABEL: "Project/Update project"},
    {ACTION: "List project (recursively)",   LABEL:
        "Project/List all files in project (recursively)"},
    {ACTION: "Status project (recursively)", LABEL:
        "Project/Query status for project (recursively)"},
    {ACTION: "Update project (recursively)",
        LABEL: "Project/Update project (recursively)"},
]


XML = r"""<?xml version="1.0" ?>
<GPS>
   <!-- Git status -->

   <action name="generic_git_local_status" show-command="false" output="none" category="">
      <shell>pwd</shell>
      <external>git --no-pager ls-files --full-name -m -c -t $2-</external>
      <shell>VCS.status_parse "Git" "%1" FALSE FALSE "%2"</shell>
      <external>git --no-pager diff --cached --name-status $2-</external>
      <shell>VCS.status_parse "Git" "%1" FALSE FALSE "%6"</shell>
   </action>

   <action name="generic_git_status" show-command="false" output="none" category="">
      <shell output="">echo "Querying status for $2-"</shell>
      <shell>pwd</shell>
      <external>git --no-pager ls-files --full-name -m -c -t $2-</external>
      <shell>VCS.status_parse "Git" "%1" FALSE FALSE "%2"</shell>
      <external>git --no-pager diff --cached --name-status $2-</external>
      <shell>VCS.status_parse "Git" "%1" FALSE FALSE "%6"</shell>
   </action>

   <action name="generic_git_diff_head" show-command="false" output="none" category="">
      <shell output="">echo "Getting comparison for $1 ..."</shell>
      <shell lang="python">git.from_git_root ("$1")</shell>
      <external>git --no-pager show HEAD:%1</external>
      <shell>dump "%1" TRUE</shell>
      <external>diff --normal -p %1 $1</external>
      <on-failure>
         <shell>base_name "$1"</shell>
         <shell>dump "%2" TRUE</shell>
         <shell>File "%1"</shell>
         <shell>File "$1"</shell>
         <shell>Hook "diff_action_hook"</shell>
         <shell>Hook.run %1 "$1" null %2 %3 "%5 [HEAD]"</shell>
         <shell>delete "%5"</shell>
         <shell>delete "%9"</shell>
      </on-failure>
      <shell>delete "%2"</shell>
   </action>

   <!-- Git add (no commit) -->

   <action name="generic_git_add_no_commit" show-command="false" output="none" category="">
      <shell output="">echo "Adding file(s) $2-"</shell>
      <external>git --no-pager add "$2-"</external>
      <on-failure>
         <shell output="">echo "Git error:"</shell>
         <shell output="">echo "%2"</shell>
      </on-failure>
   </action>

   <!-- Git commit -->

   <action name="generic_git_commit" show-command="false" output="none" category="">
      <shell output="">echo "Committing file(s) $2-"</shell>
      <shell>dump "$1" TRUE</shell>
      <external>git --no-pager commit --include -F "%1" "$2-"</external>
      <on-failure>
         <shell output="">echo "Git error:"</shell>
         <shell output="">echo "%2"</shell>
      </on-failure>
      <shell>delete "%2"</shell>
      <shell>Hook "file_changed_on_disk"</shell>
      <shell>Hook.run %1 null</shell>
   </action>

   <!-- Git annotate -->

   <action name="generic_git_annotate" show-command="false" output="none" category="">
      <shell output="">echo "Querying annotations for $1"</shell>
      <external>git --no-pager annotate "$1"</external>
      <shell>VCS.annotations_parse "Git" "$1" "%1"</shell>
   </action>

   <!-- Git history -->

   <action name="generic_git_history" show-command="false" output="none" category="">
      <shell output="">echo "Querying history for $1"</shell>
      <external>git --no-pager log --pretty=format:[%%h;%%cn;%%cd;%%s%%n%%b;] "$1"</external>
      <shell>VCS.log_parse "Git" "$1" "%1"</shell>
   </action>

   <action name="generic_git_history_text" show-command="false" output="none" category="">
      <shell output="">echo "Querying history for $1"</shell>
      <external>git --no-pager log "$1"</external>
      <shell>base_name "$1"</shell>
      <shell>dump "%2" TRUE</shell>
      <shell>Editor.edit "%1"</shell>
      <shell>Editor.set_title "%2" "Log for %3"</shell>
      <shell>Editor.set_writable "%3" FALSE</shell>
      <shell>MDI.split_vertically TRUE</shell>
      <shell>delete "%5"</shell>
   </action>

   <action name="generic_git_history_rev" show-command="false" output="none" category="">
      <shell output="">echo "Querying history for $2"</shell>
      <external>git --no-pager show $1 --pretty=format:[%%h;%%cn;%%cd;%%s%%n%%b;] "$2"</external>
      <shell>VCS.log_parse "Git" "$2" "%1"</shell>
   </action>

   <!-- Git revision -->

   <action name="generic_git_revision" show-command="false" output="none" category="">
      <shell output="">echo "Getting $2 at revision $1"</shell>
      <shell lang="python">git.from_git_root ("$2")</shell>
      <external>git --no-pager show "$1:%1"</external>
      <shell>base_name "$2"</shell>
      <shell>dump "%2" FALSE</shell>
      <shell>Editor.edit "%1"</shell>
      <shell>Editor.set_title "%2" "%3 [$1]" "%3 [$1]"</shell>
      <shell>Editor.set_writable "%3" FALSE</shell>
      <shell>delete "%4"</shell>
   </action>

   <!-- Git -->

   <vcs name="Git"
        path_style="System_Default"
        group_queries_by_directory="TRUE"
        absolute_names="FALSE" atomic_commands="TRUE"
        commit_directory="FALSE"
	administrative_directory=".git">
      <status_files       action="generic_git_status"/>
      <local_status_files action="generic_git_local_status"/>
      <diff_head          action="generic_git_diff_head"/>
      <commit             action="generic_git_commit"/>
      <add_no_commit      action="generic_git_add_no_commit"/>
      <annotate           action="generic_git_annotate"/>
      <history            action="generic_git_history"/>
      <history_text       action="generic_git_history_text"/>
      <history_revision   action="generic_git_history_rev"/>
      <revision           action="generic_git_revision"/>

      <status label="Up to date" stock="gps-emblem-vcs-up-to-date" />
      <status label="Locally modified" stock="gps-emblem-vcs-modified" />
      <status label="Property modified" stock="gps-emblem-vcs-modified" />
      <status label="Needs merge" stock="gps-emblem-vcs-needs-merge" />
      <status label="Needs update" stock="gps-emblem-vcs-needs-update" />
      <status label="Contains merge conflicts" stock="gps-emblem-vcs-has-conflicts" />
      <status label="Removed" stock="gps-emblem-vcs-removed" />
      <status label="Added" stock="gps-emblem-vcs-added" />

      <status_parser>
         <regexp>(^|\n)(.)( |\t)([^/\n]*/)*([^ \n]+)</regexp>

         <status_index>2</status_index>
         <file_index>5</file_index>

         <status_matcher label="Added">A</status_matcher>
         <status_matcher label="Locally modified">C</status_matcher>
         <status_matcher label="Up to date">H</status_matcher>
      </status_parser>

      <local_status_parser>
         <regexp>(^|\n)(.)( |\t)([^/\n]+/)*([^ \n]+)</regexp>

         <status_index>2</status_index>
         <file_index>5</file_index>

         <status_matcher label="Added">A</status_matcher>
         <status_matcher label="Locally modified">C</status_matcher>
         <status_matcher label="Up to date">H</status_matcher>
      </local_status_parser>

      <annotations_parser>
         <regexp>(........)\t\(([^\t]+)\t(....-..-..) (..:..)[^\t]+\t([^\)])(.*)(\n|$)</regexp>

         <repository_revision_index>1</repository_revision_index>
	 <author_index>2</author_index>
	 <date_index>3</date_index>
         <file_index>6</file_index>
	 <tooltip_pattern>Revision \1 on \3 \4, Author \2</tooltip_pattern>
      </annotations_parser>

      <log_parser>
         <regexp>(^|\n)\[([^;\n]+);([^;\n]*);([^;\n]*);([^;]*);\]</regexp>

         <repository_revision_index>2</repository_revision_index>
	 <author_index>3</author_index>
	 <date_index>4</date_index>
	 <log_index>5</log_index>
      </log_parser>
   </vcs>
</GPS>
"""

GPS.parse_xml(XML)
register_vcs_actions("Git", actions)
