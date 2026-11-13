uniffi::setup_scaffolding!();

#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum LookupError {
    #[error("missing")]
    Missing { id: u64 },
    #[error("unavailable")]
    Unavailable,
}

#[uniffi::export]
pub fn lookup(id: u64) -> Result<String, LookupError> {
    match id {
        0 => Ok("found".into()),
        1 => Err(LookupError::Missing { id }),
        2 => Err(LookupError::Unavailable),
        _ => panic!("lookup panic"),
    }
}

#[uniffi::export]
pub async fn lookup_async(id: u64) -> Result<String, LookupError> {
    lookup(id)
}

#[uniffi::export(callback_interface)]
pub trait Lookup: Send + Sync {
    fn lookup(&self, id: u64) -> Result<String, LookupError>;
}

#[uniffi::export]
pub fn invoke(callback: Box<dyn Lookup>, id: u64) -> Result<String, LookupError> {
    callback.lookup(id)
}

pub struct ValidatedName(String);
uniffi::custom_newtype!(ValidatedName, String);

#[uniffi::export]
pub fn name() -> Result<ValidatedName, LookupError> {
    Ok(ValidatedName("invalid".into()))
}

#[derive(uniffi::Object)]
pub struct Store;

#[uniffi::export]
impl Store {
    #[uniffi::constructor]
    pub fn new(id: u64) -> Result<Self, LookupError> {
        lookup(id)?;
        Ok(Self)
    }

    pub fn get(&self, id: u64) -> Result<String, LookupError> {
        lookup(id)
    }
}

#[uniffi::export]
pub trait ObjectError: Send + Sync + std::fmt::Debug + std::error::Error {
    fn message(&self) -> String;
}

#[derive(Debug, thiserror::Error)]
#[error("object failure")]
struct ObjectFailure;
impl ObjectError for ObjectFailure {
    fn message(&self) -> String {
        "object failure".into()
    }
}

#[uniffi::export]
pub fn object_failure() -> Result<(), std::sync::Arc<dyn ObjectError>> {
    Err(std::sync::Arc::new(ObjectFailure))
}

#[uniffi::export(callback_interface)]
#[async_trait::async_trait]
pub trait AsyncLookup: Send + Sync {
    async fn lookup(&self) -> Result<String, LookupError>;
}

#[uniffi::export]
pub async fn invoke_async(callback: Box<dyn AsyncLookup>) -> Result<String, LookupError> {
    callback.lookup().await
}
