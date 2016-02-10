CREATE TABLE task
	( id serial PRIMARY KEY
	, action text NOT NULL
	, payload jsonb NOT NULL
	, priority integer NOT NULL
	, publisehd boolean NOT NULL
	);
