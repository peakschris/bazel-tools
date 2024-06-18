load("@bazel_skylib//lib:shell.bzl", "shell")
load("@aspect_bazel_lib//lib:expand_make_vars.bzl", "expand_variables")
load("@aspect_bazel_lib//lib:paths.bzl", "BASH_RLOCATION_FUNCTION", "to_rlocation_path")
load("@aspect_bazel_lib//lib:windows_utils.bzl", "create_windows_native_launcher_script", "BATCH_RLOCATION_FUNCTION")

# Note: BASH_RLOCATION_FUNCTION 
# docs: https://github.com/bazelbuild/bazel/blob/master/tools/bash/runfiles/runfiles.bash
# set RUNFILES_LIB_DEBUG=1 to debug

_MULTIRUN_LAUNCHER_TMPL = """#!/usr/bin/env bash
set -o errexit -o nounset -o pipefail
{BASH_RLOCATION_FUNCTION}
{envs}

readonly command_path="$(rlocation {command})"
readonly instructions_path="$(rlocation {instructions})"

echo exec $command_path -f $instructions_path
exec $command_path -f $instructions_path
"""

_COMMAND_LAUNCHER_TMPL = """#!/usr/bin/env bash
set -o errexit -o nounset -o pipefail
{BASH_RLOCATION_FUNCTION}
{envs}

readonly command_path="$(rlocation {command})"
exec $command_path {args}
"""

_COMMAND_LAUNCHER_BAT_TMPL = """@echo off
SETLOCAL ENABLEEXTENSIONS
SETLOCAL ENABLEDELAYEDEXPANSION
set RUNFILES_MANIFEST_ONLY=1
{BATCH_RLOCATION_FUNCTION}
call :rlocation "{sh_script}" run_script
{envs}

call :rlocation "{command}" command_path
$command_path {args}
"""

_ENV_SET = """export {key}=\"{value}\""""

def _multirun_impl(ctx):
    is_windows = ctx.target_platform_has_constraint(ctx.attr._windows_constraint[platform_common.ConstraintValueInfo])
    runnerInfo = ctx.attr._runner[DefaultInfo]
    runner_exe = runnerInfo.files_to_run.executable

    commands = []
    tagged_commands = []
    for command in ctx.attr.commands:
        tagged_commands.append(struct(tag = str(command.label), command = command))

    for command, label in ctx.attr.tagged_commands.items():
        tagged_commands.append(struct(tag = label, command = command))

    for tag_command in tagged_commands:
        command = tag_command.command
        tag = tag_command.tag

        defaultInfo = command[DefaultInfo]
        if defaultInfo.files_to_run == None:
            fail("%s is not executable" % command.label, attr = "commands")
        exe = defaultInfo.files_to_run.executable
        if exe == None:
            fail("%s does not have an executable file" % command.label, attr = "commands")

        commands.append(struct(
            tag = tag,
            path = to_rlocation_path(ctx, exe),
        ))

    if ctx.attr.jobs < 0:
        fail("'jobs' attribute should be at least 0")

    jobs = ctx.attr.jobs
    if ctx.attr.parallel:
        print("'parallel' attribute is deprecated. Please use attribute 'jobs' instead.")
        if ctx.attr.jobs == 1:
            # If jobs is set at default value while parallel
            # is NOT set at default value, then we should respect
            # parallel to ensure backwards compatibility.
            jobs = 0
        else:
            # When both parallel and jobs are set to a non-default value,
            #   parallel == True
            #   jobs != 1
            # hard fail and ask user to only use 'jobs'.
            fail("using both 'parallel' and 'jobs' is not supported. Please use only attribute 'jobs' instead.")

    instructions = struct(
        commands = commands,
        jobs = jobs,
        quiet = ctx.attr.quiet,
        addTag = ctx.attr.add_tag,
        stopOnError = ctx.attr.stop_on_error,
    )
    instructions_file = ctx.actions.declare_file(ctx.label.name + ".json")
    ctx.actions.write(
        output = instructions_file,
        content = instructions.to_json(),
    )
    print("instructions: "+instructions.to_json())

    envs = []
    # See https://www.msys2.org/wiki/Porting/:
    # > Setting MSYS2_ARG_CONV_EXCL=* prevents any path transformation.
    if is_windows:
        envs.append(_ENV_SET.format(
            key = "MSYS2_ARG_CONV_EXCL",
            value = "*",
        ))
        envs.append(_ENV_SET.format(
            key = "MSYS_NO_PATHCONV",
            value = "1",
        ))

    bash_launcher = ctx.actions.declare_file(ctx.label.name + ".sh")
    ctx.actions.write(
        output = bash_launcher,
        content = _MULTIRUN_LAUNCHER_TMPL.format(
            envs = "\n".join(envs),
            command = to_rlocation_path(ctx, ctx.executable._runner),
            instructions = to_rlocation_path(ctx, instructions_file),
            BASH_RLOCATION_FUNCTION = BASH_RLOCATION_FUNCTION,
        ),
        is_executable = True,
    )

    launcher = create_windows_native_launcher_script(ctx, bash_launcher) if is_windows else bash_launcher

    runfiles = ctx.runfiles(ctx.files._runner + ctx.files.commands + ctx.files.tagged_commands + ctx.files.data + [bash_launcher, instructions_file])
    runfiles = runfiles.merge(ctx.attr._runfiles.default_runfiles)

    return [DefaultInfo(
        runfiles = runfiles,
        executable = launcher,
    )]

_multirun = rule(
    implementation = _multirun_impl,
    attrs = {
        "commands": attr.label_list(
            allow_empty = True,  # this is explicitly allowed - generated invocations may need to run 0 targets
            mandatory = False,
            allow_files = True,
            doc = "Targets to run",
            cfg = "target",
        ),
        "data": attr.label_list(
            doc = "The list of files needed by the commands at runtime. See general comments about `data` at https://docs.bazel.build/versions/master/be/common-definitions.html#common-attributes",
            allow_files = True,
        ),
        "tagged_commands": attr.label_keyed_string_dict(
            allow_empty = True,  # this is explicitly allowed - generated invocations may need to run 0 targets
            mandatory = False,
            allow_files = True,
            doc = "Labeled targets to run",
            cfg = "target",
        ),
        "jobs": attr.int(
            default = 1,
            doc = "The expected concurrency of targets to be executed. Default is set to 1 which means sequential execution. Setting to 0 means that there is no limit concurrency (same with parallel=True).",
        ),
        "parallel": attr.bool(
            default = False,
            doc = "Deprecated, please use 'jobs' instad.If true, targets will be run in parallel, not in the specified order",
        ),
        "add_tag": attr.bool(
            default = True,
            doc = "Include the tool in the output lines, only for parallel output",
        ),
        "quiet": attr.bool(
            default = False,
            doc = "Limit output where possible",
        ),
        "stop_on_error": attr.bool(
            default = True,
            doc = "Stop the command chain when error occurs",
        ),
        "_runfiles": attr.label(
            default = "@bazel_tools//tools/bash/runfiles",
        ),
        "_runner": attr.label(
            default = Label("@com_github_ash2k_bazel_tools//multirun"),
            cfg = "exec",
            executable = True,
        ),
        "_windows_constraint": attr.label(
            default = "@platforms//os:windows",
        ),
    },
    toolchains = [
        "@bazel_tools//tools/sh:toolchain_type",
    ],
    executable = True,
)

def multirun(**kwargs):
    tags = kwargs.get("tags", [])
    if "manual" not in tags:
        tags.append("manual")
        kwargs["tags"] = tags
    _multirun(
        **kwargs
    )

def _command_impl(ctx):
    is_windows = ctx.target_platform_has_constraint(ctx.attr._windows_constraint[platform_common.ConstraintValueInfo])
    defaultInfo = ctx.attr.command[DefaultInfo]
    executable = defaultInfo.files_to_run.executable

    envs = []
    for (key, value) in ctx.attr.environment.items() + ctx.attr.raw_environment.items():
        envs.append(_ENV_SET.format(
            key = key,
            value = " ".join([expand_variables(ctx, exp, attribute_name = "env") for exp in ctx.expand_location(value, targets = ctx.attr.data).split(" ")]),
        ))
    # See https://www.msys2.org/wiki/Porting/:
    # > Setting MSYS2_ARG_CONV_EXCL=* prevents any path transformation.
    if is_windows:
        envs.append(_ENV_SET.format(
            key = "MSYS2_ARG_CONV_EXCL",
            value = "*",
        ))
        envs.append(_ENV_SET.format(
            key = "MSYS_NO_PATHCONV",
            value = "1",
        ))

    str_args = [
        "%s" % shell.quote(ctx.expand_location(v, targets = ctx.attr.data))
        for v in ctx.attr.arguments
    ]
        
    bash_launcher = ctx.actions.declare_file(ctx.label.name + ".sh")
    ctx.actions.write(
        output = bash_launcher,
        content = _COMMAND_LAUNCHER_TMPL.format(
            envs = "\n".join(envs),
            command = to_rlocation_path(ctx, executable),
            args = " ".join(str_args + ['"$@"']),
            BASH_RLOCATION_FUNCTION = BASH_RLOCATION_FUNCTION,
        ),
        is_executable = True,
    )

    launcher = create_windows_native_launcher_script(ctx, bash_launcher) if is_windows else bash_launcher

    runfiles = ctx.runfiles(ctx.files.command + ctx.files.data + [bash_launcher])
    runfiles = runfiles.merge(ctx.attr._runfiles.default_runfiles)

    return [DefaultInfo(
        runfiles = runfiles,
        executable = launcher,
    )]

_command = rule(
    implementation = _command_impl,
    attrs = {
        "arguments": attr.string_list(
            doc = "List of command line arguments. Subject to $(location) expansion. See https://docs.bazel.build/versions/master/skylark/lib/ctx.html#expand_location",
        ),
        "data": attr.label_list(
            doc = "The list of files needed by this command at runtime. See general comments about `data` at https://docs.bazel.build/versions/master/be/common-definitions.html#common-attributes",
            allow_files = True,
        ),
        "environment": attr.string_dict(
            doc = "Dictionary of environment variables. Subject to $(location) expansion. See https://docs.bazel.build/versions/master/skylark/lib/ctx.html#expand_location",
        ),
        "raw_environment": attr.string_dict(
            doc = "Dictionary of unquoted environment variables. Subject to $(location) expansion. See https://docs.bazel.build/versions/master/skylark/lib/ctx.html#expand_location",
        ),
        "command": attr.label(
            mandatory = True,
            allow_files = True,
            executable = True,
            doc = "Target to run",
            cfg = "target",
        ),
        "_runfiles": attr.label(default = "@bazel_tools//tools/bash/runfiles"),
        "_windows_constraint": attr.label(default = "@platforms//os:windows"),
    },
    toolchains = [
        "@bazel_tools//tools/sh:toolchain_type",
    ],
    executable = True,
)

def command(**kwargs):
    tags = kwargs.get("tags", [])
    if "manual" not in tags:
        tags.append("manual")
        kwargs["tags"] = tags
    _command(
        **kwargs
    )
