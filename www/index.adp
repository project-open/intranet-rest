<if @json_p@>@json;noquote@</if>
<else>

	<master>
	<property name="title">@page_title@</property>
	<property name="context">@context_bar@</property>

	<h1>@page_title@</h1>
	<p>Please see the <a href="http://www.project-open.com/en/package-intranet-rest"
        >online REST documentation</a> for details.<br>&nbsp;<br>

	<listtemplate name="object_types"></listtemplate>
	
</else>
