"""A small JSON-Schema subset validator + schema-building helpers.

Supported keywords: type (string or list), enum, minLength, maxLength, minimum, maximum, items,
minItems, maxItems, required, properties, additionalProperties (false only). That is exactly what the
tool input and output schemas use; both are validated with this one implementation (inputs at call time,
outputs in tests / dev mode) so the documented contract cannot drift from the code.
"""

from __future__ import annotations

import json
from typing import Any

from ..errors import INVALID_ARGUMENT, HiveError


def _is(t: str, v: Any) -> bool:
    if t == "string":
        return isinstance(v, str)
    if t == "integer":
        return isinstance(v, int) and not isinstance(v, bool)
    if t == "number":
        return isinstance(v, (int, float)) and not isinstance(v, bool)
    if t == "boolean":
        return isinstance(v, bool)
    if t == "array":
        return isinstance(v, list)
    if t == "object":
        return isinstance(v, dict)
    if t == "null":
        return v is None
    return False


def _name(v: Any) -> str:
    return "null" if v is None else type(v).__name__


def validate(schema: dict, value: Any, path: str = "arguments") -> None:
    """Raise HiveError(INVALID_ARGUMENT) describing the first violation."""
    def bad(msg: str):
        raise HiveError(INVALID_ARGUMENT, f"{path}: {msg}", {"path": path})
    types = schema.get("type")
    if types is not None:
        ts = types if isinstance(types, list) else [types]
        if not any(_is(t, value) for t in ts):
            bad(f"expected {' or '.join(ts)}, got {_name(value)}")
    if "enum" in schema and value not in schema["enum"]:
        bad(f"must be one of {schema['enum']}")
    if isinstance(value, str):
        if "minLength" in schema and len(value) < schema["minLength"]:
            bad(f"must be at least {schema['minLength']} characters")
        if "maxLength" in schema and len(value) > schema["maxLength"]:
            bad(f"must be at most {schema['maxLength']} characters")
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        if "minimum" in schema and value < schema["minimum"]:
            bad(f"must be >= {schema['minimum']}")
        if "maximum" in schema and value > schema["maximum"]:
            bad(f"must be <= {schema['maximum']}")
    if isinstance(value, list):
        if "minItems" in schema and len(value) < schema["minItems"]:
            bad(f"needs at least {schema['minItems']} items")
        if "maxItems" in schema and len(value) > schema["maxItems"]:
            bad(f"allows at most {schema['maxItems']} items")
        if "items" in schema:
            for i, item in enumerate(value):
                validate(schema["items"], item, f"{path}[{i}]")
    if isinstance(value, dict):
        for k in schema.get("required", []):
            if k not in value:
                bad(f"missing required property '{k}'")
        props = schema.get("properties", {})
        if schema.get("additionalProperties") is False:
            extra = sorted(set(value) - set(props))
            if extra:
                raise HiveError(INVALID_ARGUMENT, f"{path}: unknown parameter(s) {extra}",
                                {"path": path, "allowed": sorted(props)},
                                hint=f"Allowed parameters: {', '.join(sorted(props)) or '(none)'}")
        for k, sub in props.items():
            if k in value:
                validate(sub, value[k], f"{path}.{k}")


# ------------------------------------------------------------------ builders
def prop(type_, description: str, **extra) -> dict:
    return {"type": type_, "description": description, **extra}


def text(description: str, max_chars: int = 20000, **extra) -> dict:
    return prop("string", description, maxLength=max_chars, **extra)


def ident(description: str) -> dict:
    return prop("string", description, minLength=1, maxLength=120)


def obj_in(properties: dict, required: tuple | list = ()) -> dict:
    """Input schema: strict (unknown parameters are rejected with the list of valid ones)."""
    return {"type": "object", "properties": properties, "required": list(required), "additionalProperties": False}


def obj_out(properties: dict, required: list | None = None) -> dict:
    """Output schema: listed properties are required by default; extra properties are allowed."""
    return {"type": "object", "properties": properties,
            "required": list(properties) if required is None else list(required)}


S = {"type": "string"}
NS = {"type": ["string", "null"]}
I = {"type": "integer"}
NI = {"type": ["integer", "null"]}
B = {"type": "boolean"}
OBJ = {"type": "object"}
NOBJ = {"type": ["object", "null"]}


def arr(item: dict) -> dict:
    return {"type": "array", "items": item}


# ------------------------------------------------------- what clients are shown vs. what the server enforces
def _free_form_object(node: Any) -> bool:
    return isinstance(node, dict) and node.get("type") == "object" and not node.get("properties")


def client_schema(schema: dict) -> dict:
    """The schema ADVERTISED in tools/list: a portable JSON-Schema subset.

    Gemini-backed clients (Google Antigravity) validate every tool declaration and refuse the whole request when a
    single one carries a construct they do not support, which shows up as a server that looks connected while the
    agent fails. Two constructs in Hive's strict internal schemas are affected:
      * `additionalProperties` (every tool) is not advertised. It is still ENFORCED: `validate()` rejects unknown
        parameters server-side and names the valid ones, so no safety is lost.
      * an object without declared properties (free-form `state`) is advertised as a JSON-encoded string;
        `coerce_args()` turns it back into an object, and a real object is still accepted.
    Empty `required` lists are dropped as well (invalid in strict JSON Schema validators).
    """
    def conv(node: Any, top: bool = False) -> Any:
        if not isinstance(node, dict):
            return node
        out: dict[str, Any] = {}
        for k, v in node.items():
            if k == "additionalProperties":
                continue
            if k == "required" and not v:
                continue
            if k == "properties" and isinstance(v, dict):
                out[k] = {n: conv(sub) for n, sub in v.items()}
            elif k == "items":
                out[k] = conv(v)
            else:
                out[k] = v
        if not top and _free_form_object(out):
            desc = str(out.get("description", "")).rstrip()
            return {"type": "string", "description": (desc + " " if desc else "") +
                    "Pass a JSON-encoded object, for example '{\"key\": \"value\"}'."}
        return out
    return conv(schema, top=True)


def coerce_args(schema: dict, args: Any) -> Any:
    """Accept a JSON-encoded string where the internal schema wants a free-form object (see client_schema)."""
    if not isinstance(args, dict):
        return args
    fixed = None
    for name, sub in schema.get("properties", {}).items():
        if _free_form_object(sub) and isinstance(args.get(name), str):
            try:
                value = json.loads(args[name])
            except ValueError:
                value = None
            if not isinstance(value, dict):
                raise HiveError(INVALID_ARGUMENT, f"arguments.{name}: expected a JSON object (or a string containing one)",
                                {"path": f"arguments.{name}"}, hint=f"Pass {name} as a JSON object such as {{\"key\": \"value\"}}.")
            fixed = dict(args) if fixed is None else fixed
            fixed[name] = value
    return args if fixed is None else fixed
