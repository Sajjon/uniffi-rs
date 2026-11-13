{%- call swift::docstring_value(protocol_docstring, 0) %}{% endcall %}
public protocol {{ protocol_name }}: AnyObject, Sendable {
    {% for meth in methods.iter() -%}
    {%- for typed in [true, false] %}
    {%- if !typed || (config.experimental_typed_throws() && meth.throws()) %}
    {%- if config.experimental_typed_throws() && meth.throws() %}
    {% if typed %}#if compiler(>=6.0){% else %}#else{% endif %}
    {%- endif %}
    {%- call swift::docstring(meth, 4) %}{% endcall %}
    func {{ meth.name()|fn_name }}({% call swift::arg_list_protocol(meth) %}{% endcall %}) {% call swift::is_async(meth) -%}{% endcall %}{% call swift::declaration_throws(meth, typed) %}{% endcall -%}
    {%- match meth.return_type() -%}
    {%- when Some with (return_type) %} -> {{ return_type|type_name -}}
    {%- else -%}
    {%- endmatch %}
    {%- if !typed && config.experimental_typed_throws() && meth.throws() %}
    #endif
    {%- endif %}
    {%- endif %}
    {%- endfor %}
    {% endfor %}
}
