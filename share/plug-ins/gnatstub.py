"""
This file adds support for the gnatstub utility.
This external tool creates the Ada body from an Ada spec.
"""


import GPS
import gps_utils
import os


class OnExit(object):

    def __init__(self, file):
        self.file = file

    def on_exit(self, proc, status, output):
        # ??? For some reason, status is always "0"
        GPS.Project.recompute()
        f2 = self.file.other_file()

        if os.path.isfile(f2.path):
            GPS.EditorBuffer.get(f2)
        else:
            GPS.Locations.parse(output, "gnatstub")


@gps_utils.interactive(
    category="Editor",
    filter=gps_utils.in_ada_file,
    name="generate body")
def generate_body():
    """
Run gnatstub on the current Ada spec to generate a matching
body file.
    """
    GPS.MDI.save_all()
    proj = GPS.current_context().project()
    file = GPS.current_context().file()
    command = '"%s" stub "%s" %s "%s" "%s"' % (
        gps_utils.get_gnat_driver_cmd(),
        "-P%s" % proj.file().path if proj else "",
        GPS.Project.scenario_variables_cmd_line("-X"),
        file.path,
        file.directory())

    proc = GPS.Process(
        command,
        task_manager=True,
        show_command=True,
        on_exit=OnExit(file).on_exit)
    proc.wait()
