class ReportsController < InheritedResources::Base
  belongs_to :node, :optional => true, :finder => :find_by_url!
  protect_from_forgery :except => [:create, :upload]

  before_filter :raise_if_enable_read_only_mode, :only => [:new, :edit, :update, :destroy]
  before_filter :handle_raw_post, :only => [:create, :upload]

  def index
    index! do |success,failure|
      success.html do
        if params[:kind] == "inspect"
          @reports = paginate_scope Report.inspections
        else
          @reports = paginate_scope Report.applies
        end
      end
    end
  end

  def create
    if SETTINGS.disable_legacy_report_upload_url
      render :text => "Access Denied, this url has been disabled, try /reports/upload", :status => 403
    else
      upload
    end
  end

  def upload
    begin
      Report.create_from_yaml(params[:report][:report])
      render :text => "Report successfully uploaded"
    rescue => e
      error_text = "ERROR! ReportsController#upload failed:"
      Rails.logger.debug error_text
      Rails.logger.debug e.message
      render :text => "#{error_text} #{e.message}", :status => 406
    end
  end

  def diff
    @my_report = Report.find(params[:id])

    if params[:baseline_type] == "self"
      @baseline_report = @my_report.node.baseline_report
      @diff_error_message = "Node '#{@my_report.node.name}' does not have a baseline report set." unless @baseline_report
    else
      node = Node.find_by_name(params[:baseline_host])

      if node
        @baseline_report = node.baseline_report
        @diff_error_message = "Node '#{params[:baseline_host]}' does not have a baseline report set." unless @baseline_report
      else
        @diff_error_message = "Node '#{params[:baseline_host]}' does not exist."
      end
    end

    unless @diff_error_message
      @diff = @baseline_report.diff(@my_report)
      @resource_statuses = Report.divide_diff_into_pass_and_fail(@diff)
    end
  end

  def make_baseline
    report = Report.find( params[:id] )
    report.baseline!
    redirect_to report
  end

  def search
    flash[:errors] = []
    inspected_resources = ResourceStatus.latest_inspections.order("nodes.name")

    @title = params[:file_title].to_s.strip
    @content = params[:file_content].to_s.strip

    if params[:file_title] == nil and params[:file_content] == nil
      # Don't do anything; user just navigated to the search page
    else
      if !@title.present?
        flash[:errors] << "Please specify the file title to search for"
      end
      if !@content.present?
        flash[:errors] << "Please specify the file content to search for"
      elsif !is_md5?(@content)
        flash[:errors] << "#{@content} is not a valid md5 checksum"
      end
      if flash[:errors].empty?
        @matching_files = inspected_resources.by_file_title(@title).by_file_content(@content)
        @unmatching_files = inspected_resources.by_file_title(@title).without_file_content(@content)
      end
    end
  end

  def baselines
    if request.format == :json
      limit = params[:limit].to_i
      search_term = params[:term].gsub(/([\\%_])/, "\\\\\\1")
      prefix_matches = Report.baselines.where(["host LIKE ?", "#{search_term}%"]).order("host ASC").limit(limit).map(&:host)
      substring_matches = Report.baselines.where(["host LIKE ?", "%#{search_term}%"]).order("host ASC").limit(limit).map(&:host)
      matches = (prefix_matches + substring_matches).uniq[0,limit]
      render :text => matches.to_json, :content_type => 'application/json'
    else
      render :status => 406
    end
  end

  private

  def collection
    get_collection_ivar || set_collection_ivar(
      request.format == :html ? 
        paginate_scope(end_of_association_chain) : 
        end_of_association_chain
    )
  end

  def handle_raw_post
    report = params[:report]
    params[:report] = {}
    case report
    when String
      params[:report][:report] = report
    when nil
      params[:report][:report] = request.raw_post
    when Hash
      params[:report] = report
    end
  end

end
