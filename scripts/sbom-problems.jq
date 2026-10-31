# The problems of a completed CycloneDX SBOM of the image (FY-0027), one per
# line. Used by check-licenses.sh. Inputs: $closure, the store paths of the
# image, one per line; $deny, identifiers of licenses that forbid
# redistribution, one per line; $root, the store path the SBOM is generated
# from.
#
# The SBOM describes the closure of $root: the store paths of the image and
# $root itself, a text file that only names the contents of the image.
# sbomnix puts $root in .metadata.component; it is excluded in case a
# component has it too. A component is a derivation and names all its
# outputs, also those the image does not contain, such as -dev or -man: it is
# extra only when none of its outputs is in the image. Components without
# nix:output_path name no store path and are only checked for licenses.

# nonempty_lines: the lines of a string that are not empty.
def nonempty_lines: split("\n") | map(select(. != ""));

# nonempty_string: the input if it is a non-empty string, else nothing.
def nonempty_string: strings | select(. != "");

# has_licenses: whether a component lists any license.
def has_licenses: (.licenses // []) | length > 0;

# license_key: the SPDX id, else the name, of a license entry; null unless
# the entry has an object with a non-empty string id or name.
def license_key: [.license? | objects | (.id | nonempty_string) // (.name | nonempty_string)] | first;

# outputs: the store paths a component names as its outputs.
def outputs: [.properties[]? | select(.name == "nix:output_path") | .value | splits("\\s+") | nonempty_string];

# image_paths: the store paths of the image.
def image_paths: $closure | nonempty_lines;

# store_components: the outputs of each component that names any, except $root.
def store_components: [.components[]? | outputs | select(length > 0) | select(index($root) | not)];

# in_image: whether any of the outputs of a component is in the image.
def in_image: any(.[]; . as $output | image_paths | index($output));

# missing_store_paths: store paths of the image that no component names.
def missing_store_paths: image_paths - (store_components | add // []) | .[];

# extra_components: the first output of components that are not in the image.
def extra_components: store_components[] | select(in_image | not) | .[0];

# unlicensed: the problem of a component without licenses.
def unlicensed: "unlicensed \(.name)";

# malformed($name): the problem of licenses or a license entry of component
# $name that cannot be read.
def malformed($name): "malformed \(tojson) \($name)";

# forbidden($name): the problem of a license entry of component $name that
# forbids redistribution; nothing for other licenses.
def forbidden($name):
  license_key as $key | select($deny | nonempty_lines | index($key)) | "forbidden \($key) \($name)";

# component_problems: the problems of a component, in the order of its licenses.
def component_problems:
  .name as $name
  | if has_licenses | not then unlicensed
    elif .licenses | type != "array" then .licenses | malformed($name)
    else .licenses[] | if license_key == null then malformed($name) else forbidden($name) end
    end;

(missing_store_paths | "missing \(.)"),
(extra_components | "extra \(.)"),
(.components[]? | component_problems)
