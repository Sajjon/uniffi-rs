import Foundation
{%- import "macros.swift" as swift %}
{% include "RuntimeErrors.swift" %}
fileprivate struct RustBuffer {}
{% include "TypedThrows.swift" %}
{{ harness }}
