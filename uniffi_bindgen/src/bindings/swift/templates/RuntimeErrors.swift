{%- if config.experimental_typed_throws() %}
#if compiler(>=6.0)
public enum {{ config.error_namespace() }} {
{% call swift::runtime_error_decl("public", config.runtime_error_base_name()) %}{% endcall %}
}
fileprivate typealias UniffiInternalError = {{ config.runtime_error_name() }}
#else
{% call swift::runtime_error_decl("fileprivate", "UniffiInternalError") %}{% endcall %}
#endif
{%- else %}
{%- call swift::runtime_error_decl("fileprivate", "UniffiInternalError") %}{% endcall %}
{%- endif %}

