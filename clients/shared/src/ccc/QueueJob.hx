package ccc;

typedef QueueJob<T> = {
	var id :JobId;
	var item :T;
	var parameters :JobParams;
}
