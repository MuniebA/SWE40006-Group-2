from flask import Blueprint, render_template, redirect, url_for, flash, request
from flask_login import login_user, logout_user, login_required, current_user
from ..models import User, Student
from ..forms import LoginForm, RegistrationForm, StudentProfileForm
from .. import db
from datetime import datetime

auth = Blueprint('auth', __name__)


@auth.route('/login', methods=['GET', 'POST'])
def login():
    if current_user.is_authenticated:
        if current_user.is_admin():
            return redirect(url_for('admin.dashboard'))
        return redirect(url_for('student.dashboard'))

    form = LoginForm()
    if form.validate_on_submit():
        user = User.query.filter_by(username=form.username.data).first()
        if user is not None and user.verify_password(form.password.data):
            login_user(user, form.remember_me.data)
            next_page = request.args.get('next')
            if next_page:
                return redirect(next_page)
            elif user.is_admin():
                return redirect(url_for('admin.dashboard'))
            else:
                return redirect(url_for('student.dashboard'))
        flash('Invalid username or password.', 'danger')
    return render_template('auth/login.html', form=form, title='Login', now=datetime.now())


@auth.route('/logout')
@login_required
def logout():
    logout_user()
    flash('You have been logged out.', 'info')
    return redirect(url_for('auth.login'))


@auth.route('/register', methods=['GET', 'POST'])
def register():
    if current_user.is_authenticated:
        return redirect(url_for('index'))

    form = RegistrationForm()
    if form.validate_on_submit():
        user = User(
            username=form.username.data,
            email=form.email.data,
            role='student'
        )
        user.password = form.password.data
        db.session.add(user)
        db.session.commit()
        flash('Account created successfully! Please complete your profile.', 'success')
        login_user(user)
        return redirect(url_for('auth.complete_profile'))
    return render_template('auth/register.html', form=form, title='Register', now=datetime.now())


@auth.route('/complete-profile', methods=['GET', 'POST'])
@login_required
def complete_profile():
    if current_user.is_admin() or (current_user.is_student() and current_user.student):
        return redirect(url_for('index'))

    form = StudentProfileForm()
    if form.validate_on_submit():
        student = Student(
            user_id=current_user.id,
            name=form.name.data,
            age=form.age.data,
            contact=form.contact.data
        )
        db.session.add(student)
        db.session.commit()
        flash('Profile completed successfully!', 'success')
        return redirect(url_for('student.dashboard'))
    return render_template('auth/complete_profile.html', form=form, title='Complete Profile', now=datetime.now())


@auth.route('/profile', methods=['GET', 'POST'])
@login_required
def profile():
    if current_user.is_admin():
        return redirect(url_for('admin.dashboard'))

    student = current_user.student
    if not student:
        return redirect(url_for('auth.complete_profile'))

    form = StudentProfileForm(obj=student)
    if form.validate_on_submit():
        student.name = form.name.data
        student.age = form.age.data
        student.contact = form.contact.data
        db.session.commit()
        flash('Profile updated successfully!', 'success')
        return redirect(url_for('student.dashboard'))
    return render_template('auth/profile.html', form=form, title='My Profile', now=datetime.now())
