"""
This plugin provides a function to reformat the current line
or selection.
It tries to do a number of things, which can be configured
separately to suit your work style.

This function is available in GPS through the action
"Format Selection", which is bound to the <tab> key by default.
"""

import GPS
from gps_utils import interactive, make_interactive, in_editor
import text_utils
import pygps
import aliases
import align
from gi.repository import Gtk


if not GPS.Logger("PREVENT_ALIGN_ON_TAB").active:
    tabs_align_selection = GPS.Preference("Editor/tabs_align_selection")
    tabs_align_selection.create(
        "Align selection on tab", "boolean",
        "Whether <tab> should also align arrows, use clauses and "
        "assignments (:=) when multiple lines are selected.",
        True)


@interactive(name='Format selection', category='Editor',
             filter="Writable source editor")
def smart_tab():
    """
    This action is the default binding for the tab key, and will
    apply different behaviors depending on the current context.

    When expanding aliases, <tab> will move to the next field.
    Otherwise, when multiple lines are selected it will try to align
    special sequences like ":", "=>", "use" and ":=".
    Finally, it will automatically indent the selected lines.
    """

    editor = GPS.EditorBuffer.get()

    # When expanding aliases, <tab> should move to the next field

    if aliases.is_in_alias_expansion(editor):
        aliases.toggle_next_field(editor)
        return

    # If multiple lines are selected, perform various alignments

    if not GPS.Logger("PREVENT_ALIGN_ON_TAB").active:
        if tabs_align_selection.get():
            start = editor.selection_start()
            end = editor.selection_end()

            if abs(start.line() - end.line()) >= 1:
                align.align_colons()
                align.align_arrows()
                align.align_use_clauses()
                align.align_assignments()

    # if it's a python code, do it in python way
    if editor.file().language() == "python":
        d = python_tab_indent(editor,
                              editor.selection_start(),
                              editor.selection_end())

    # Otherwise, reformat the current selection

    else:
        action = GPS.Action("Autoindent selection")
        if not action.execute_if_possible():
            editor.insert(editor.current_view().cursor(), "\t")


def python_tab_indent(e, beginning, end, indenting_block=False):
    """
    Indent python code when tab is pressed
    1 if performed on line, indent line by 4, move cursor relatively
    2 if performed on block, indent each non-empty line, move cursor
      to the end of selection area after finish
    """

    # if multiple lines selected, indent each one by order
    if beginning.line() != end.line():
        for i in range(beginning.line(), end.line() + 1):
            tmp = e.get_chars(e.at(i, 1), e.at(i, 1).end_of_line())

            # if line is not empty, indent by 4
            if tmp.strip("\n").strip(" ") is not "":
                indent = python_tab_indent(e, e.at(i, 0),
                                           e.at(i, end.column()), True)
    else:
        s = e.get_chars(end.beginning_of_line(), end.end_of_line())
        n = len(s) - len(s.lstrip(" "))
        indent = 4 - n % 4
        if indenting_block and n % 4 != 0:
            indent += 4
        e.insert(e.at(end.line(), 1), " " * indent)

    e.main_cursor().move(e.at(end.line(), end.column() + indent))
    return indent


def should_escape(context):
    """ Filter for the 'smart escape' action """
    editor = GPS.EditorBuffer.get(force=False, open=False)

    if editor:
        if aliases.is_in_alias_expansion(editor):
            return True

        if editor.has_slave_cursors():
            return True

        if GPS.Action("Cancel completion").can_execute():
            return True

    if [c for c in GPS.MDI.children()
       if (c.is_floating() and c.get_child().__class__ == GPS.GUI)]:
        return True

    return False


@interactive(name='smart escape', category='General',
             key="Escape", filter=should_escape)
def smart_escape():
    """
    This action is the default binding for the Escape key, and will, in order:
      - close the completion window (if any)
      - interrupt the current alias expansion (if any).
      - remove multiple cursors
      - remove the completion if it exists
      - close the most recent floating view, if any
    """

    def do_something():
        """ React to the Esc key, and return True iff something was done. """

        editor = GPS.EditorBuffer.get(force=False, open=False)

        if editor:
            if aliases.is_in_alias_expansion(editor):
                aliases.exit_alias_expand(editor)
                return True

            if editor.has_slave_cursors():
                editor.remove_all_slave_cursors()
                return True

            if GPS.Action("Cancel completion").execute_if_possible():
                return True

        c = [c for c in GPS.MDI.children()
             if (c.is_floating() and c.get_child().__class__ == GPS.GUI)]

        if c:
            # Do this rather than c[0].close() to give the toplevel window
            # a chance to react to delete_event.
            c[0].get_child().pywidget().get_toplevel().close()
            return True

    if do_something():
        # We did something in reaction to the ESC key being pressed:
        # force a refresh of the context, so the filter gets reevaluated.
        GPS.current_context(True)
