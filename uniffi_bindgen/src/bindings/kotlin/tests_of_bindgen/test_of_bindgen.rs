use uniffi_meta::{FnMetadata, MethodMetadata, ObjectImpl, ObjectMetadata, Type};

use crate::interface::Function;

use super::*;

fn config() -> Config {
    let config = Config::default();

    config
}

#[test]
fn test_kotlin_bindgen() {
    let config = config();

    let mut ci = ComponentInterface::new("foo");

    for i in 0..2 {
        ci.add_function_definition(Function::from(FnMetadata {
            module_path: "fizz".to_owned(),
            name: format!("global_func_{i}"),
            is_async: false,
            inputs: vec![],
            return_type: Some(Type::Boolean),
            throws: None,
            checksum: None,
            docstring: None,
        }))
        .unwrap();
    }

    let object_meta = ObjectMetadata {
        module_path: "buzz".to_owned(),
        name: "Fizz".to_owned(),
        remote: false,
        imp: ObjectImpl::Struct,
        docstring: None,
    };
    ci.add_object_meta(object_meta.clone()).unwrap();

    for i in 0..2 {
        ci.add_method_meta(MethodMetadata {
            module_path: object_meta.module_path.clone(),
            self_name: object_meta.name.clone(),
            name: format!("method_{i}"),
            is_async: false,
            inputs: vec![],
            return_type: Some(Type::Boolean),
            throws: None,
            takes_self_by_arc: true,
            checksum: None,
            docstring: None,
        })
        .unwrap()
    }

    let settings = GenerationSettings {
        cdylib: None,
        out_dir: Utf8PathBuf::default(),
        try_format_code: false,
    };

    let mut components = vec![Component {
        ci,
        config: config.clone(),
    }];

    KotlinBindingGenerator
        .update_component_configs(&settings, &mut components)
        .unwrap();

    let component = components.iter().next().unwrap();

    let kotlin = generate_bindings(&component.config, &component.ci).unwrap();
    println!("{}", kotlin);
    // let expected = include_str!("fixture_kotlin.kt");
    // pretty_assertions::assert_eq!(kotlin, expected)
}
