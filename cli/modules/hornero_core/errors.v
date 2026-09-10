module hornero_core

// ErrorClass is the horneroctl domain error taxonomy.
// Exit-code contract: 0 ok, 2 flag/usage errors, 1 everything else.
pub enum ErrorClass {
	ok
	user
	config
	env
	external
	internal
	usage_flags
}

// DomainError is a structured error returned by core (no printing here).
pub struct DomainError {
pub:
	class   ErrorClass
	code    string
	message string
}

pub fn (e DomainError) msg() string {
	return e.message
}

pub fn (c ErrorClass) exit_code() int {
	return match c {
		.ok { 0 }
		.usage_flags { 2 }
		.user, .config, .env, .external, .internal { 1 }
	}
}

pub fn (e DomainError) exit_code() int {
	return e.class.exit_code()
}

pub fn err_user(code string, message string) DomainError {
	return DomainError{
		class:   .user
		code:    code
		message: message
	}
}

pub fn err_config(code string, message string) DomainError {
	return DomainError{
		class:   .config
		code:    code
		message: message
	}
}

pub fn err_env(code string, message string) DomainError {
	return DomainError{
		class:   .env
		code:    code
		message: message
	}
}

pub fn err_external(code string, message string) DomainError {
	return DomainError{
		class:   .external
		code:    code
		message: message
	}
}

pub fn err_internal(code string, message string) DomainError {
	return DomainError{
		class:   .internal
		code:    code
		message: message
	}
}

pub fn err_usage(code string, message string) DomainError {
	return DomainError{
		class:   .usage_flags
		code:    code
		message: message
	}
}
