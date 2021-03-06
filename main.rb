require "nokogiri"
require "rest-client"
require "json"
#require "set"

SUPPORTED_SCHEMA_TYPES = ["string", "integer", "array", "boolean"]

entity_page = "https://kanka.io/en-US/docs/1.0/entities"
entities = Hash.new
entities["Character"] = "https://kanka.io/en-US/docs/1.0/characters"
entities["Family"] = "https://kanka.io/en-US/docs/1.0/families"
entities["Location"] = "https://kanka.io/en-US/docs/1.0/locations"
entities["Organisation"] = "https://kanka.io/en-US/docs/1.0/organisations"
entities["Item"] = "https://kanka.io/en-US/docs/1.0/items"
entities["Note"] = "https://kanka.io/en-US/docs/1.0/notes"
entities["Event"] = "https://kanka.io/docs/1.0/events"
entities["Race"] = "https://kanka.io/docs/1.0/races"
entities["Quest"] = "https://kanka.io/docs/1.0/quests"
entities["Journal"] = "https://kanka.io/docs/1.0/journals"
entities["Ability"] = "https://kanka.io/docs/1.0/abilities"
entities["Tag"] = "https://kanka.io/en-US/docs/1.0/tags"

entities["Timeline"] = "https://kanka.io/docs/1.0/timelines"
entities["Conversation"] = "https://kanka.io/docs/1.0/conversations"
entities["Dice_Roll"] = "https://kanka.io/docs/1.0/dice-rolls"

entities["Maps"] = "https://kanka.io/en-US/docs/1.0/maps"
entities["Map_Marker"] = "https://kanka.io/en-US/docs/1.0/map_markers"
entities["Map_Group"] = "https://kanka.io/docs/1.0/map_groups"
entities["Map_Layer"] = "https://kanka.io/docs/1.0/map_layers"

entities["Attribute"] = "https://kanka.io/docs/1.0/attributes"
entities["Entity_Event"] = "https://kanka.io/docs/1.0/entity-events"
entities["Entity_File"] = "https://kanka.io/docs/1.0/entity-files"
entities["Entity_Inventory"] = "https://kanka.io/docs/1.0/inventory"
#entities["Entity_Mention"] = "https://kanka.io/docs/1.0/entity-mentions"
entities["Entity_Note"] = "https://kanka.io/docs/1.0/entity-notes"
entities["Entity_Tag"] = "https://kanka.io/docs/1.0/entity-tags"
entities["Relation"] = "https://kanka.io/docs/1.0/relations"
entities["Inventory"] = "https://kanka.io/docs/1.0/entity-inventory"
entities["Entity_Ability"] = "https://kanka.io/docs/1.0/entity-abilities"

entities["Timeline_Element"] = "https://kanka.io/en-US/docs/1.0/timeline-elements"

#Non-entities
entities["Timeline_Era"] = "https://kanka.io/en-US/docs/1.0/timeline-eras"




def fetch_parameters(url)
	parameters = Array.new
	response = RestClient.get url
	html = Nokogiri::HTML(response.body)
	rows = nil
	if (url.eql? "https://kanka.io/en-US/docs/1.0/entities")
		rows = html.xpath("//th[text() = 'Attribute']/../../../tbody/tr")
	else
		rows = html.xpath("//th[text() = 'Parameter']/../../../tbody/tr")
	end


	#Collect the parameters
	rows.each do |row|
		param = Hash.new
		tds = row.css("td")
		name = tds[0].content.strip
		type = tds[1].content.strip
		description = tds[2].content.strip
		code_blocks = tds[2].css("code")
		if (code_blocks.length > 0)
			enums = Array.new
			code_blocks.each do |code_block|
				enums.push(code_block.content.strip)
			end
			if ((enums.length == 1) && (enums[0].eql? "#"))
				#do nothing
			else
				param[:enums] = enums
			end
		end
		is_required = (type.downcase.include? "required") ? true : false
		type = type.split(" ")[0]

		param[:name] = name
		param[:type] = type
		param[:description_html] = description
		param[:required] = is_required

		parameters.push(param)
	end

	return parameters
end

def is_entity_parameter(parameters, name)
	parameters.each do |param|
		if (param[:name].eql? name)
			return true
		end
	end
	return false
end

def generate_schema_json(entity_name, entity_params, base_entity_params)
	puts "Processing #{entity_name}"
	schema = Hash.new
	schema[:type] = "object"
	schema[:extends] = {"$ref" => "entity.json"}
	
	properties = Hash.new

	entity_params = entity_params.sort_by { |p| p[:name] }

	entity_params.each do |param|
		is_entity_parameter = is_entity_parameter(base_entity_params, param[:name])
		is_supported_type = SUPPORTED_SCHEMA_TYPES.include? param[:type]
		if (is_entity_parameter || !is_supported_type)
			#puts "[#{entity_name}] Skipping #{param[:name]}"
			next
		end

		schema_param = Hash.new
		schema_param[:required] = param[:required]
		# Make IDs a long
		if (param[:name].end_with? "_id")
			schema_param[:type] = "string"
			schema_param[:format] = "utc-millisec"
		elsif ((param[:type].eql? "string") && param[:enums])
			schema_param[:type] = "string"
			schema_param[:enum] = param[:enums]
		elsif (param[:type].eql? "array")
			puts "-- array #{param[:name]}"
			schema_param[:type] = "array"
			schema_param[:items] = {
				"type" => "string"
			}
		else
			schema_param[:type] = param[:type]
		end
		
		properties[param[:name]] = schema_param
	end

	schema[:properties] = properties
	return schema
end

param_map = Hash.new
base_entity_params = fetch_parameters(entity_page)
entities.each do |type, url|
	params = fetch_parameters(url)
	schema = generate_schema_json(type, params, base_entity_params)

	#Collect metrics on how often the parameters appear
	schema[:properties].each do |param_name|
		unless (param_map.has_key? param_name)
			param_map[param_name] = Array.new
		end
		param_map[param_name].push(type)
	end

	file_name = "./out/#{type.downcase}.json"

	File.open(file_name, "w") do |f|
	  f.write(JSON.pretty_generate(schema))
	end
end

puts "Total entities: #{entities.length}"
total_entities = entities.length
param_map.each do |param, types|
	if (types.length >= total_entities)
		puts "Consider adding #{param} to base entity"
	end
end
