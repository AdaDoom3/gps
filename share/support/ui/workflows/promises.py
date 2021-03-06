"""
This package provides a number of classes and functions to help write
workflows. See the full description of workflows in workflows/__init__.py
"""

import time
from time_utils import *

import GPS
import re
from pygps import process_all_events
from gi.repository import GLib


class Promise(object):
    """
    A promise is a wrapper object around an asynchronous computation.
    - The client of the promise calls promise.then(use_callback) on the promise
      to register the action that he wants executed when the promise's result
      is available.
    - The creator of the promise calls resolve on the promise when the result
      is ready, which will notify the client via the callback.

    Promises are one of the two low-level support concepts for workflows
    (along with python's yield keyword). They can be used to implement your
    own asynchronous programming functions, if the other functions in this
    module are not sufficient.

    For instance, let's assume you want to query data from a web server.
    Since such a query could take a while, we do not want to block GPS during
    that time. So we need to do this query in the background.

        class WebQuery(Thread):
            def __init__(self, url, promise):
                self.promise = promise
                self.url = url
            def run(self):
                # Running in a separate thread: connect to the server and
                # retrieve the document, for instance with urllib. Since this
                # is a separate thread, it doesn't block GPS
                doc = urllib.urlopen(self.url)

                # Let the promise no that we now have the info
                self.promise.resolve(doc)

        def query_from_server(*args):
            p = Promise()
            # run the query in the background
            w = WebQuery(url='...', promise=p)
            return p

    One could now use the `query_from_server` directly from a GPS workflow,
    but just to show the low-level of using promises:

        # We receive the document, as per the call to resolve() above
        def when_query_is_done(doc):
            ...

        # The following call is not blocking at all
        query_from_server(...).then(when_query_is_done)

    """

    PENDING = -1
    RESOLVED = 0
    REJECTED = 1

    def __init__(self):
        self.__success = []  # Called when the promise is resolved
        self.__failure = []  # Called when the promise is rejected
        self.__result = None   # The result of the promise
        self.__state = Promise.PENDING

    def then(self, success=None, failure=None):
        """
        Register user defined callback to be called when the promise is
        resolved or rejected.

        :param success: a function called when the promise is resolved
           (or immediately if the promise has already been resolved).
           It receives as parameter the value passed when calling
           `self.resolve()` (or, if that was also a promise, the value of
           that promise once it has been resolved).
           `success` is called at most once (and never if the promise is
           rejected).
           If this function returns a promise, that promise will be
           resolved before calling the next promise in the chain (see the
           description on the return value below).

        :param failure: a function called when the promise is rejected
           (or immediately if the promise has already been rejected).
           If receives as a parameter the value passed when calling
           `self.reject()`
           `failure` is called at most once (and never if the promise is
           resolved).

        :return: a new promise, which will be resolved with the return
           value of `success`, or rejected with the return value of
           `failure`. This way, promises can be chained more easily:

               Promise().then(on_promise1_done).then(on_promise2_done)

           where on_promise1_done is called with the return value of the
           first promise, and on_promise2_done is called with the
           return value of on_promise1_done.
           If `success` also return a promise, the value of that promise will
           be used to resolve the result of `then`.
        """
        ret = Promise()

        def __fullfill(value):
            ret.resolve(success(value) if success else value)

        def __reject(reason):
            ret.reject(failure(reason) if failure else reason)

        if self.__state == Promise.RESOLVED:
            __fullfill(self.__result)
        elif self.__state == Promise.REJECTED:
            __reject(self.__result)
        else:
            self.__success.append(__fullfill)
            self.__failure.append(__reject)
        return ret

    def resolve(self, result=None):
        """
        Set the value of the promise.
        This automatically calls the callbacks set by the user.
        :param result: any type
           This is the result of the promise, and is passed to the callback.
        """
        if self.__state == Promise.PENDING:
            if isinstance(result, Promise):
                result.then(self.resolve, self.reject)
            else:
                self.__state = Promise.RESOLVED
                self.__result = result  # in case we call then() later
                for s in self.__success:
                    s(result)

                # Release all listeners, for garbage collecting, since the
                # state of the promise can't change anymore, and listeners are
                # only called once.
                self.__success = None
                self.__failure = None

    def reject(self, reason=None):
        """
        The promise cannot be fullfilled after all, so call the appropriate
        callbacks. `reason` should not be a Promise.
        """
        if self.__state == Promise.PENDING:
            self.__state = Promise.REJECTED
            self.__result = reason
            for s in self.__failure:
                s(reason)

            self.__success = None
            self.__failure = None


def timeout(msecs):
    """
    This primitive allows the user to delay execution of the rest of a workflow
    for msecs milliseconds.

       def my_func():
           bar()
           yield timeout(200)   # wait 200ms
           bar()

    When possible, it is better to use `wait_idle` to wait until GPS is not
    busy doing anything else, rather than wait an explicit delay, which might
    depend on the CPU load for instance.
    """
    p = Promise()

    def timeout_handler():
        p.resolve()
        return False

    GLib.timeout_add(msecs, timeout_handler)
    return p


def wait_idle():
    """
    This primitive allows the writer of a workflow to wait until all event have
    been handled, and resume execution of the workflow in an idle callback
    """
    p = Promise()
    process_all_events()
    GLib.idle_add(lambda: p.resolve())
    return p


def wait_tasks():
    """
    This primitive allows the user to delay the execution of the rest of a
    workflow until all active tasks are terminated. If you are waiting on
    tasks that you spawned yourself, it is better to use ProcessWrapper
    or TargetWrapper below to spawn the task.
    """

    p = Promise()

    def timeout_handler():
        if not GPS.Task.list():
            process_all_events()
            GLib.idle_add(lambda: p.resolve())
            return False
        return True   # will try again

    GLib.timeout_add(200, timeout_handler)
    return p


def modal_dialog(action_fn, msecs=300):
    """
    This primitive executes a blocking function in the context of a workflow.
    This should rarely be used, but is sometimes needed for some modal dialogs
    that block GPS without executing the python script.
    Example:
        yield modal_dialog(
            300, lambda: GPS.execute_action('open project properties'))
    """
    p = Promise()

    def __on_timeout():
        p.resolve()
        return False

    def __start_action():
        # Use Glib's timeout_add, since GPS.Timeout doesn't seem to be run
        # correctly when running python's Gtk.Dialog.run (for instance for the
        # coding standard editor).
        GLib.timeout_add(msecs, __on_timeout)
        action_fn()
        return False

    # Since action is blocking, and we want modal_dialog to return the
    # promise, we need to start the action in a timeout.
    GLib.timeout_add(10, __start_action)
    return p


def idle_modal_dialog(action_fn):
    """
    Similar to `modal_dialog()`, but waits until GPS is finished processing
    events, instead of a specific timeout.
    """
    p = Promise()

    def __on_idle():
        GLib.idle_add(lambda: p.resolve())
        action_fn()

    GLib.idle_add(__on_idle)
    return p


def hook(hook_name):
    """
    This primitive allows the writer of a workflow to connect to a hook once,
    as if it were a function, and get the parameters of the hook as return
    values. For example:

        _, file = yield hook("buffer_edited")

    This will wait until the "buffer_edited" hook is triggered, and the file
    will be stored in the file variable.
    """
    p = Promise()

    def hook_handler(hook_params):
        GPS.Hook(hook_name).remove(hook_handler)
        p.resolve()

    GPS.Hook(hook_name).add(hook_handler)
    return p


class ProcessWrapper(object):
    """
    ProcessWrapper is an advanced process manager
    It makes a promise (yield object of the promise class) when user:
        1 - want to wait for match in output
        2 - want to wait until process finish
    and the corresponding promises are answered with user defined
    handler (functions) when:
        1 - the pattern matches or timeout.
        2 - the process is terminated by GPS.

    Example of use:

        def my_func():
            p = ProcessWrapper(['ls'])
            status, output = yield p.wait_until_terminate()

    """

    def __init__(self, cmdargs=[], spawn_console=False):
        """
        Initialize and run a process with no promises,
        no user-defined pattern to match,
        but a omnipotent regexp that catches everything.
        The process has empty output and two flags saying that
        the process is unfinished and no pattern has matched yet.

        If spawn_console is True, a console is spawned to display the
        process output. This console also allows the user to relaunch
        the associated process with a "Relaunch" button in the console
        toolbar.
        """

        # __final_promise = about termination
        self.__final_promise = None

        # __current_promise = about on waiting wish for match something
        self.__current_promise = None

        # __current_pattern = regexp that user waiting for in the output
        self.__current_pattern = None

        # __whether the __current_promise is answered
        self.__current_answered = False

        # __output = a buffer for current output of self.__process
        self.__output = ""

        # __whether process has finished
        self.finished = False

        # handler of process will be created -> start running
        self.__command = cmdargs

        # The console associated with the process.
        # Created only if spawn_console is set to True.
        self.__console = None

        # Launch the command
        self.__process = GPS.Process(
            command=self.__command,
            regexp=".+",
            on_match=self.__on_match,
            on_exit=self.__on_exit)

        # Save the start time
        self.__start_time = time.time()

        # If requested, spawn a console to display the process output
        if spawn_console:
            toolbar_name = cmdargs[0] + '_toolbar'

            self.__console = GPS.Console(
                name=cmdargs[0],
                accept_input=False,
                on_destroy=self.__on_console_destroy,
                toolbar_name=toolbar_name,
                give_focus_on_create=False)
            self.__action = GPS.Action('launch ' + cmdargs[0])

            # Create the associated action and relaunch button if it
            # does not exist yet.
            if not self.__action.exists():
                self.__action.create(
                    on_activate=self.__relaunch,
                    description='relaunch the spawned process',
                    icon='gps-refresh-symbolic')
                self.__action.button(
                    toolbar=toolbar_name,
                    label='Relaunch')

    def __on_match(self, process, match, unmatch):
        """
        Called by GPS everytime there's output comming
        """

        # Update all output returned by the process
        # and store it as a private buffer
        self.__output += match + unmatch

        # Display the output on the spawned console, if any
        if self.__console:
            self.__console.write(unmatch + match)

        # check if user has issued some pattern to match
        if self.__current_pattern:
            p = re.search(self.__current_pattern, self.__output)

            # if the pattern is found, update the output to remaining and
            # answer the promise with True-->found it
            if p:
                self.__current_answered = True
                self.__output = self.__output[p.span()[1]::]
                self.__current_promise.resolve((True, self.__output))

    def __on_exit(self, process, status, remaining_output):
        """
           Call by GPS when the process is finished.
           Final_promise will be solved with status
           Current_promise will be solved with False
        """
        # get end timestamp
        end_time = time.time()

        # mark my process as finished
        self.finished = True

        # check if there's unanswered match promises
        # if there is --> pattern has never been found, answer with False
        if self.__current_promise and not self.__current_answered:
            self.__current_promise.resolve((False, ""))

        # check if I had made a promise to finish the process
        # if there is, answer with whatever the exit status is
        if self.__final_promise:
            self.__final_promise.resolve((status, remaining_output))

        # output the exit status on the attached console, if any
        if self.__console:
            output = "\n" + TimeDisplay.get_timestamp(end_time)

            if not status:
                output += " process terminated successfully"
            else:
                output += " process exited with status " + str(status)

            output += ", elapsed time: " + TimeDisplay.get_elapsed(
                self.__start_time, end_time) + "\n"

            self.__console.write(output)

    def wait_until_match(self, pattern=None, timeout=0):
        """
        Called by user. Make a promise to them that:
        I'll let you know when the pattern is matched/never matches and return
        the remaining output if the pattern matched.
        * Promise made here will be answered with a tuple:
            (True/False, remaining_output)
        """
        # process has already terminated, return nothing
        if self.finished:
            return None

        # keep the pattern info and return my promise
        self.__current_pattern = pattern
        self.__current_promise = Promise()

        # if user defines a timeout, set up to
        # close output check after that timeout

        if timeout > 0:
            GLib.timeout_add(timeout, self.__on_timeout)

        return self.__current_promise

    def wait_until_terminate(self):
        """
        Called by user. Make a promise to them that:
        I'll let you know when the process is finished
        * Promise made here will be answered with a tuple:
            (exit status, output)
        """

        # process has already terminated, return nothing
        if self.finished:
            return None

        # process is still running, return my promise
        self.__final_promise = Promise()
        return self.__final_promise

    def __on_timeout(self):
        """
        Called by GPS when it's timeout for a pattern to appear in output.
        """

        # current promise unanswered --> too late, it fails
        if not self.__current_answered:
            self.__current_pattern = None
            self.__current_answered = True
            # answer the promise with False
            self.__current_promise.resolve((False, ""))
        return False

    def terminate(self):
        """
        Called by the user to force the process to end and resolve
        the associated promises.
        Interrupt the attached process.
        """

        # get end timestamp
        end_time = time.time()

        # Interrupt the process, if any
        if not self.finished:
            self.__process.interrupt()

            if self.__console:
                self.__console.write(
                    "\n<^C> process interrupted (elapsed time: %s)\n" %
                    TimeDisplay.get_elapsed(self.__start_time, end_time))

    def __on_console_destroy(self, console):
        """
        Called when the console is being destroyed.
        Interrupt the attached process.
        """
        self.__process.interrupt()
        self.finished = True
        self.__console = None

    def __relaunch(self):
        """
        Called when clicking on the "Relaunch" button of the
        console toolbar.
        Terminate the process and relaunch it again.
        """

        self.terminate()
        self.__process = GPS.Process(
            command=self.__command,
            regexp=".+",
            on_match=self.__on_match,
            on_exit=self.__on_exit)
        self.__start_time = time.time()


class DebuggerWrapper(object):
    """
       DebuggerWrapper is a debbuger (essentially a process in GPS) manager
       It make a promise (yield object of the promise class) when user:
           want to send a command to debugger

       and the corresponding promises are answered after
           1 the debugger is not busy, execute the command required
           2 timeout
    """

    # static variable for interval that the manager checks whether
    # the debugger is busy, in milliseconds
    __query_interval = 200

    def __init__(self, f, reuse_existing=True,
                 remote_target='', remote_protocol=''):
        """
           Initialize a manager, begin a debugger on the given file
           with no timers, no promises, no command.

           The optional ``remote_target`` and ``remote_protocol`` parameters
           are used to initialize a remote debugging session when spawning the
           debugger. When not specified, the ``IDE'Program_Host`` and
           ``IDE'Communication_Protocol`` are used if present in the .gpr
            project file.
        """

        if reuse_existing:
            try:
                # handler for debugger
                self.__debugger = GPS.Debugger.get()

                # Raise the debugger's console if we are reusing an existing
                # one.
                GPS.MDI.get_by_child(
                    self.__debugger.get_console()).raise_window()

                # if we reach this, a debugger is running: interrupt it
                GPS.execute_action("/Debug/Interrupt")

                # Try to reconnect to the previous remote connection, if any
                GPS.execute_action("/Debug/Debug/Connect to board...")
            except:
                self.__debugger = GPS.Debugger.spawn(
                    executable=f,
                    remote_target=remote_target,
                    remote_protocol=remote_protocol)
                pass
        else:
            self.__debugger = GPS.Debugger.spawn(f)

        # current on waiting promise
        self.__this_promise = None

        # the command to be sent
        self.__next_cmd = None

        # the output returned after send __next_cmd
        self.__output = None

        # regular checker that checks if debugger is busy
        self.__timer = None

        # deadline for __next_cmd and __this_promise
        self.__deadline = None

    def __is_busy(self, timeout):
        """
           Called by GPS at each interval.
        """

        # if the debugger is not busy
        if not self.__debugger.is_busy():

            # remove all timers
            self.__remove_timers()

            # and if there's cmd to run, send it
            if self.__next_cmd is not None:

                if self.__next_cmd is not "":
                    self.__output = self.__debugger.send(
                        cmd=self.__next_cmd,
                        show_in_console=True)
                    self.__next_cmd = None
                    self.__remove_timers()
                    self.__this_promise.resolve(self.__output)

                # "" cmd are default value when making promise,
                # it's also a maker for pure checker
                else:
                    self.__this_promise.resolve(True)

    def __on_cmd_timeout(self, timeout):
        """
           Called by GPS at when the deadline defined by user is reached
        """

        # remove all timers
        self.__remove_timers()

        # answer the promise with the output
        if self.__this_promise:
            self.__next_cmd = None
            self.__this_promise.resolve(self.__output)

    def __remove_timers(self):
        """
           Called in timers to remove both: prepare for new timer registration
        """
        if self.__deadline:
            try:
                self.__deadline.remove()
            except:
                pass
            self.__deadline = None

        if self.__timer:
            try:
                self.__timer.remove()
            except:
                pass
            self.__timer = None

    def wait_and_send(self, cmd="", timeout=0, block=False):
        """
           Called by user on request for command within deadline (time)
           Promise returned here will be answered with: output

           This method may also function as a pure block-debugger-and-wait-
           until-not-busy call, when block=True.
           Promise returned for this purpose will be answered with: True/False
        """

        self.__this_promise = Promise()
        self.__next_cmd = cmd
        self.__output = None

        self.__timer = GPS.Timeout(self.__query_interval, self.__is_busy)

        # only register deadline for real command waiting
        if not block:
            if timeout > 0:
                self.__deadline = GPS.Timeout(timeout, self.__on_cmd_timeout)
        return self.__this_promise

    def get(self):
        """
           Accessible interface for my debugger
        """
        return self.__debugger


class TargetWrapper():
    """
    TargetWrapper is a manager that build target and return
    a thenable promise before execute the target
    The promise will be answered with the exit status when
    the target finishes
    """
    def __init__(self, target_name):
        """
           Build the target and initialize promise to None
        """

        # handler for my target
        self.__target = GPS.BuildTarget(target_name)

        # promise about building this target
        self.__promise = None

    def wait_on_execute(self, main_name="", file=None, extra_args=None):
        """
        Called by the user. Will execute the target and return a promise.
        Promises made here will be answered with: exit status of the build.
        """

        self.__promise = Promise()
        self.__target.execute(main_name=main_name,
                              synchronous=False,
                              file=file,
                              extra_args=extra_args,
                              on_exit=self.__on_exit)
        return self.__promise

    def __timeout_after_exit(self):
        self.__promise.resolve(self.__status)
        return False

    def __on_exit(self, status):
        """
           Called by GPS when target finishes executing.
           Will answer the promise with exiting status.
        """

        self.__status = status
        GLib.timeout_add(200, self.__timeout_after_exit)
