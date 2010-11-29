require 'rubygems'
gem 'opentox-ruby-api-wrapper', '= 1.6.2.1'
require 'opentox-ruby-api-wrapper'

class MajorityModel
  include DataMapper::Resource
  property :id, Serial
  property :uri, String, :length => 255
  property :created_at, DateTime
  property :classification, Boolean
  
  property :title, String, :length => 255, :default => "Majority Model"
  property :mean, String, :length => 255
  property :creator, String, :length => 255, :default => "Test user"
  property :format, String, :length => 255, :default => "n/a"
  property :algorithm, String, :length => 255
  property :predictedVariables, String, :length => 255
  property :independentVariables, String, :length => 255, :default => "n/a"
  property :dependentVariables, String, :length => 255
  property :trainingDataset, String, :length => 255
  
  def date
    return @created_at.to_s
  end
end

MajorityModel.auto_upgrade!

post '/:class/model/:id' do
  
  classification = check_classification(params)
  
  model = MajorityModel.get(params[:id])
  halt 404, "Model #{params[:id]} not found." unless model
  
  halt 404, "No dataset_uri parameter." unless params[:dataset_uri]
  LOGGER.debug "Dataset: " + params[:dataset_uri].to_s
  dataset = OpenTox::Dataset.find(params[:dataset_uri])
  
  prediction = OpenTox::Dataset.new 
  prediction.creator = model.uri
  prediction.features << model.predictedVariables
  
  response['Content-Type'] = 'text/uri-list'
  task_uri = OpenTox::Task.as_task("Predict dataset", url_for("/"+params[:class]+"/model/"+model.id.to_s, :full), params) do |task|
     i = 0
     dataset.compounds.each do |compound_uri|
        prediction.compounds << compound_uri
        prediction.data[compound_uri] = [] unless prediction.data[compound_uri]
        if classification
          tuple = { 
              "classification" => model.mean,
              "confidence" => 1, }
          prediction.data[compound_uri] << {model.predictedVariables => tuple}
        else
          prediction.data[compound_uri] << {model.predictedVariables => model.mean}
        end
        i += 1
        task.progress( i / dataset.compounds.size.to_f * 100 )
     end
  #   puts "done"
     prediction.save.chomp
  end
  halt 202,task_uri
end

def check_classification(params)
  case params[:class]
  when "class"
    return true
  when "regr"
    return false
  else
    halt 400,"Neither 'class' nor 'regr'"
  end
end

get '/:class/model/:id' do
  
  classification = check_classification(params)
  
  model = MajorityModel.first(:id => params[:id], :classification => classification)
  halt 404, "Model #{params[:id]} not found." unless model
  
  accept = request.env['HTTP_ACCEPT']
  accept = "application/rdf+xml" if accept == '*/*' or accept == '' or accept.nil?
  case accept
  when "application/rdf+xml"
    content_type "application/rdf+xml"
    OpenTox::Model::Generic.to_rdf(model)
  when "application/x-yaml"
    content_type "application/x-yaml"
    model.to_yaml
  when /text\/html/
    content_type "text/html"
    OpenTox.text_to_html model.to_yaml
  else
    halt 400,"header not supported "+accept.to_s
  end
end

post '/:class/algorithm/?' do
  
  classification = check_classification(params)
  
  halt 404, "No dataset_uri parameter." unless params[:dataset_uri]
  halt 404, "No prediction_feature parameter." unless params[:prediction_feature]
  
	LOGGER.debug "Dataset: " + params[:dataset_uri].to_s
  dataset = OpenTox::Dataset.find(params[:dataset_uri])
  halt 404, "No feature #{params[:prediction_feature]} in dataset #{params[:dataset_uri]}. (features: "+
    dataset.features.inspect+")" unless dataset.features and dataset.features.include?(params[:prediction_feature])
  
  feature = params[:prediction_feature]
  compounds = dataset.compounds
  
  vals = {}
  compounds.each do |c|
    val = dataset.get_value(c,feature)
    vals[val] = ( vals.has_key?(val) ? vals[val] : 0 ) + 1
  end
  max = -1
  max_val = nil
  vals.each do |k,v|
    if v>max
      max = v
      max_val = k
    end
  end
  
  LOGGER.debug "Creating Majority Model, mean is: "+max_val.to_s
  
  model = MajorityModel.new
  model.save # needed to create id
  model.uri = url_for("/"+params[:class]+"/model/"+model.id.to_s, :full)
  model.mean = max_val
  model.algorithm = url_for("/"+params[:class]+"/algorithm", :full)
  model.trainingDataset = params[:dataset_uri]
  model.predictedVariables = params[:prediction_feature]+"_maj"
  #model.independentVariables = ""
  model.dependentVariables = params[:prediction_feature]
  model.classification = classification
  
  raise "could not save" unless model.save
  
  response['Content-Type'] = 'text/uri-list'
  model.uri
end

get '/:class/algorithm' do
  classification = check_classification(params)
  owl = OpenTox::Owl.create 'Algorithm', url_for("/"+params[:class]+"/algorithm",:full)
  owl.set 'title',"Majority Classification"
  owl.set 'date',Time.now
  
  case request.env['HTTP_ACCEPT'].to_s
  when /text\/html/
    content_type "text/html"
    OpenTox.text_to_html owl.rdf
  else
    content_type 'application/xml+rdf'
    owl.rdf
  end
end

get '/:class/model' do
  classification = check_classification(params)
  params[:classification] = params["class"]=="class"
  params.delete("class")
  uri_list = MajorityModel.all(params).collect{|m| m.uri}.join("\n")+"\n"
  
  case request.env['HTTP_ACCEPT'].to_s
  when /text\/html/
    content_type "text/html"
    OpenTox.text_to_html uri_list 
  else
    content_type 'text/uri-list'
    uri_list
  end
end


get '/:class' do
  check_classification(params)
  uri_list = [url_for("/"+params[:class]+"/algorithm", :full), url_for("/"+params[:class]+"/model", :full)].join("\n")+"\n"
  
  case request.env['HTTP_ACCEPT'].to_s
  when /text\/html/
    content_type "text/html"
    OpenTox.text_to_html uri_list 
  else
    content_type 'text/uri-list'
    uri_list
  end 
end

get '/?' do
  uri_list =  [url_for("/class", :full), url_for("/regr", :full)].join("\n")+"\n"
  
  case request.env['HTTP_ACCEPT'].to_s
  when /text\/html/
    content_type "text/html"
    OpenTox.text_to_html uri_list 
  else
    content_type 'text/uri-list'
    uri_list
  end 
end
  
