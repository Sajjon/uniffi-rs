use super::*;

fn config() -> Config {
    let config = Config::default();

    config
}

#[test]
fn test_kotlin_bindgen() {
    let config = config();
    let ci = ComponentInterface::new("foobar");
    let bindgen = KotlinBindingGenerator;

    let settings = GenerationSettings {
        cdylib: None,
        out_dir: Utf8PathBuf::default(),
        try_format_code: false,
    };

    let mut components = vec![Component {
        ci,
        config: config.clone(),
    }];

    bindgen
        .update_component_configs(&settings, &mut components)
        .unwrap();

    let component = components.iter().next().unwrap();

    let kotlin = generate_bindings(&component.config, &component.ci).unwrap();
    // println!("🔮🔮🔮🔮🔮\n{}\n🔮🔮🔮🔮🔮", kotlin);
    let expected = include_str!("fixture_kotlin.kt");
    pretty_assertions::assert_eq!(kotlin, expected)
}
