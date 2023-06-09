"expand_template rule"

load("@bazel_skylib//lib:dicts.bzl", "dicts")
load(":expand_locations.bzl", _expand_locations = "expand_locations")
load(":expand_variables.bzl", _expand_variables = "expand_variables")
load("//lib:stamping.bzl", "STAMP_ATTRS", "maybe_stamp")

def _expand_substitutions(ctx, substitutions):
    result = {}
    for k, v in substitutions.items():
        result[k] = " ".join([
            _expand_variables(ctx, e, outs = [ctx.outputs.out], attribute_name = "substitutions")
            for e in _expand_locations(ctx, v, ctx.attr.data).split(" ")
        ])
    return result

def _expand_template_impl(ctx):
    substitutions = _expand_substitutions(ctx, ctx.attr.substitutions)
    expand_template_info = ctx.toolchains["@aspect_bazel_lib//lib:expand_template_toolchain_type"].expand_template_info
    stamp = maybe_stamp(ctx)
    if stamp:
        substitutions = dicts.add(substitutions, _expand_substitutions(ctx, ctx.attr.stamp_substitutions))
        substitutions_out = ctx.actions.declare_file("{}_substitutions.json".format(ctx.label.name))
        ctx.actions.write(
            output = substitutions_out,
            content = json.encode(substitutions),
        )

        inputs = [
            ctx.file.template,
            stamp.volatile_status_file,
            stamp.stable_status_file,
            substitutions_out,
        ]

        args = ctx.actions.args()
        args.add(ctx.file.template)
        args.add(ctx.outputs.out)
        args.add(substitutions_out)
        args.add(stamp.volatile_status_file)
        args.add(stamp.stable_status_file)
        args.add(ctx.attr.is_executable)

        ctx.actions.run(
            arguments = [args],
            outputs = [ctx.outputs.out],
            inputs = inputs,
            executable = expand_template_info.bin,
        )
    else:
        ctx.actions.expand_template(
            template = ctx.file.template,
            output = ctx.outputs.out,
            substitutions = substitutions,
            is_executable = ctx.attr.is_executable,
        )

    all_outs = [ctx.outputs.out]
    runfiles = ctx.runfiles(files = all_outs)
    return [DefaultInfo(files = depset(all_outs), runfiles = runfiles)]

expand_template_lib = struct(
    doc = """Template expansion

This performs a simple search over the template file for the keys in substitutions,
and replaces them with the corresponding values.

Values may also use location templates as documented in
[expand_locations](https://github.com/aspect-build/bazel-lib/blob/main/docs/expand_make_vars.md#expand_locations)
as well as [configuration variables](https://docs.bazel.build/versions/main/skylark/lib/ctx.html#var)
such as `$(BINDIR)`, `$(TARGET_CPU)`, and `$(COMPILATION_MODE)` as documented in
[expand_variables](https://github.com/aspect-build/bazel-lib/blob/main/docs/expand_make_vars.md#expand_variables).
""",
    implementation = _expand_template_impl,
    toolchains = ["@aspect_bazel_lib//lib:expand_template_toolchain_type"],
    attrs = dicts.add({
        "data": attr.label_list(
            doc = "List of targets for additional lookup information.",
            allow_files = True,
        ),
        "is_executable": attr.bool(
            doc = "Whether to mark the output file as executable.",
        ),
        "out": attr.output(
            doc = "Where to write the expanded file.",
            mandatory = True,
        ),
        "stamp_substitutions": attr.string_dict(
            doc = """Mapping of strings to substitutions.

            There are overlayed on top of substitutions when stamping is enabled
            for the target.

            Substitutions can contain $(execpath :target) and $(rootpath :target)
            expansions, $(MAKEVAR) expansions and {{STAMP_VAR}} expansions when
            stamping is enabled for the target.
            """,
        ),
        "substitutions": attr.string_dict(
            doc = """Mapping of strings to substitutions.

            Substitutions can contain $(execpath :target) and $(rootpath :target)
            expansions, $(MAKEVAR) expansions and {{STAMP_VAR}} expansions when
            stamping is enabled for the target.
            """,
        ),
        "template": attr.label(
            doc = "The template file to expand.",
            mandatory = True,
            allow_single_file = True,
        ),
    }, **STAMP_ATTRS),
)

expand_template = rule(
    doc = expand_template_lib.doc,
    implementation = expand_template_lib.implementation,
    toolchains = expand_template_lib.toolchains,
    attrs = expand_template_lib.attrs,
)
