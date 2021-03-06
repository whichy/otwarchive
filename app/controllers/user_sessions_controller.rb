class UserSessionsController < ApplicationController

  # I hope this isn't catching unwanted exceptions; it's hard to locate
  # where exactly the exception is thrown in case of no cookies. --rebecca
  rescue_from ActionController::InvalidAuthenticityToken, :with => :show_auth_error

  layout "session"
  before_filter :admin_logout_required
  skip_before_filter :store_location


  def show_auth_error
    redirect_to "/auth_error.html"
  end

  def new
  end

  def create
    if openid = request.env['rack.openid.response']
      @openid_url = openid.display_identifier
      Rails.logger.debug "OpenID #{openid.status}: #{@openid_url}"
      case openid.status
      when :missing
        message = "Sorry, the OpenID server couldn't be found"
      when :cancel
        message = "OpenID verification was canceled"
      when :failure
        message = "Sorry, the OpenID verification failed"
      when :success
        user = User.where(:identity_url => openid.display_identifier).first
        if user
          flash[:notice] = ts("Successfully logged in.")
          @current_user = UserSession.create(user, params[:remember_me]).record
          redirect_to(@current_user) and return
        else
          message = "Sorry, we couldn't find a user with that OpenID URL"
        end
      else
        message = "Sorry, the OpenID verification process failed"
      end
      flash.now[:error] = message
      params[:use_openid] = true
      render :action => 'new'
    elsif params[:openid_url]
      @openid_url = params[:openid_url]
      @openid_url = "http://#{@openid_url}" unless @openid_url.match("http://")
      begin
        @openid_url = OpenID.normalize_url(@openid_url)
      rescue OpenID::DiscoveryFailure
        message = "Sorry, that doesn't seem to be the correct format for an OpenID URL."
      else
        user = User.find_by_identity_url(@openid_url)
        if !user
          message = "Sorry, we couldn't find a user with that OpenID URL"
        else
          response.headers['WWW-Authenticate'] = Rack::OpenID.build_header(:identifier => @openid_url)
          Rails.logger.debug response.headers
          head 401 and return
        end
      end
      flash.now[:error] = message
      render :action => 'new'
    elsif params[:user_session]
      @user_session = UserSession.new(params[:user_session])
      if @user_session.save
        flash[:notice] = ts("Successfully logged in.")
        @current_user = @user_session.record
        redirect_back_or_default(@current_user)
      else
        if params[:user_session][:login] && user = User.find_by_login(params[:user_session][:login])
          # we have a user
          if user.recently_reset? && params[:user_session][:password] == user.activation_code
            if user.updated_at > 1.week.ago
              # we sent out a generated password and they're using it
              # log them in
              @current_user = UserSession.create(user, params[:remember_me]).record
              # and tell them to change their password
              redirect_to change_password_user_path(@current_user) and return
            else
              message = ts("The password you entered has expired. Please click the 'forgot password' link below.")
            end
          elsif user.active?
            message = ts("The password you entered doesn't match our records. Please try again or click the 'forgot password' link below.")
          else
            message = ts("You'll need to activate your account before you can log in. Please check your email or contact support.")
          end
        else
          message = ts("We couldn't find that user name in our database. Please try again.")
        end
        flash.now[:error] = message
        @user_session = UserSession.new(params[:user_session])
        render :action => 'new'
      end
    end
  end

  def destroy
    @user_session = UserSession.find
    if @user_session
      @user_session.destroy
      flash[:notice] = ts("Successfully logged out.")
    end
    redirect_back_or_default root_url
  end

end
