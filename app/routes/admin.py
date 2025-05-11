from flask import Blueprint, render_template, redirect, url_for, flash, request
from flask_login import login_required, current_user
from ..models import User, Student, Class, Registration, Setting
from ..forms import ClassForm, SettingsForm
from .. import db
from functools import wraps
import calendar
from sqlalchemy import func
from datetime import datetime

admin = Blueprint('admin', __name__)

# Custom decorator for admin-only routes


def admin_required(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if not current_user.is_authenticated or not current_user.is_admin():
            flash('You do not have permission to access this page.', 'danger')
            return redirect(url_for('auth.login'))
        return f(*args, **kwargs)
    return decorated_function


@admin.route('/dashboard')
@login_required
@admin_required
def dashboard():
    # Get summary statistics for the dashboard
    total_students = Student.query.count()
    total_classes = Class.query.count()
    pending_registrations = Registration.query.filter_by(
        status='pending').count()

    # Get recent registrations
    recent_registrations = Registration.query.order_by(
        Registration.created_at.desc()).limit(5).all()

    return render_template('admin/dashboard.html',
                           title='Admin Dashboard',
                           total_students=total_students,
                           total_classes=total_classes,
                           pending_registrations=pending_registrations,
                           recent_registrations=recent_registrations, now=datetime.now())

# Student Management


@admin.route('/students')
@login_required
@admin_required
def student_list():
    students = Student.query.all()
    return render_template('admin/student_list.html', title='Student Management', students=students, now=datetime.now())


@admin.route('/students/<int:student_id>')
@login_required
@admin_required
def student_detail(student_id):
    student = Student.query.get_or_404(student_id)
    registrations = Registration.query.filter_by(student_id=student.id).all()
    return render_template('admin/student_detail.html', title=f'Student: {student.name}', student=student, registrations=registrations, now=datetime.now())


@admin.route('/students/<int:student_id>/delete', methods=['POST'])
@login_required
@admin_required
def delete_student(student_id):
    student = Student.query.get_or_404(student_id)
    user = User.query.get(student.user_id)

    db.session.delete(student)
    if user:
        db.session.delete(user)
    db.session.commit()

    flash(f'Student {student.name} has been deleted.', 'success')
    return redirect(url_for('admin.student_list'))

# Class Management


@admin.route('/classes')
@login_required
@admin_required
def class_list():
    classes = Class.query.all()
    # Group classes by day
    classes_by_day = {}
    days_order = {'monday': 0, 'tuesday': 1, 'wednesday': 2,
                  'thursday': 3, 'friday': 4, 'saturday': 5, 'sunday': 6}

    for day in days_order:
        day_classes = [c for c in classes if c.day_of_week == day]
        if day_classes:
            classes_by_day[day] = sorted(day_classes, key=lambda x: x.class_no)

    return render_template('admin/class_list.html',
                           title='Class Management',
                           classes_by_day=classes_by_day,
                           days_order=days_order, now=datetime.now())


@admin.route('/classes/add', methods=['GET', 'POST'])
@login_required
@admin_required
def add_class():
    form = ClassForm()
    if form.validate_on_submit():
        new_class = Class(
            class_no=form.class_no.data,
            day_of_week=form.day_of_week.data,
            start_time=form.start_time.data,
            end_time=form.end_time.data,
            teacher=form.teacher.data
        )
        db.session.add(new_class)
        db.session.commit()
        flash(
            f'Class {new_class.class_no} on {new_class.day_of_week.capitalize()} has been added.', 'success')
        return redirect(url_for('admin.class_list'))
    return render_template('admin/class_form.html', form=form, title='Add New Class', now=datetime.now())


@admin.route('/classes/<int:class_id>/edit', methods=['GET', 'POST'])
@login_required
@admin_required
def edit_class(class_id):
    class_obj = Class.query.get_or_404(class_id)
    form = ClassForm(obj=class_obj)

    # Store class ID for custom validation
    form.class_id = class_id

    if form.validate_on_submit():
        class_obj.class_no = form.class_no.data
        class_obj.day_of_week = form.day_of_week.data
        class_obj.start_time = form.start_time.data
        class_obj.end_time = form.end_time.data
        class_obj.teacher = form.teacher.data
        db.session.commit()
        flash(f'Class {class_obj.class_no} has been updated.', 'success')
        return redirect(url_for('admin.class_list'))
    return render_template('admin/class_form.html', form=form, title='Edit Class', class_obj=class_obj, now=datetime.now())


@admin.route('/classes/<int:class_id>/delete', methods=['POST'])
@login_required
@admin_required
def delete_class(class_id):
    class_obj = Class.query.get_or_404(class_id)
    db.session.delete(class_obj)
    db.session.commit()
    flash(
        f'Class {class_obj.class_no} on {class_obj.day_of_week.capitalize()} has been deleted.', 'success')
    return redirect(url_for('admin.class_list'))

# Registration Management


@admin.route('/registrations')
@login_required
@admin_required
def registration_list():
    status = request.args.get('status', 'all')

    if status == 'pending':
        registrations = Registration.query.filter_by(
            status='pending').order_by(Registration.created_at.desc()).all()
    elif status == 'approved':
        registrations = Registration.query.filter_by(
            status='approved').order_by(Registration.created_at.desc()).all()
    elif status == 'rejected':
        registrations = Registration.query.filter_by(
            status='rejected').order_by(Registration.created_at.desc()).all()
    else:
        registrations = Registration.query.order_by(
            Registration.created_at.desc()).all()

    return render_template('admin/registration_list.html',
                           title='Registration Management',
                           registrations=registrations,
                           current_status=status, now=datetime.now())


@admin.route('/registrations/<int:registration_id>/approve', methods=['POST'])
@login_required
@admin_required
def approve_registration(registration_id):
    registration = Registration.query.get_or_404(registration_id)
    registration.status = 'approved'
    db.session.commit()
    flash(
        f'Registration for {registration.student.name} has been approved.', 'success')
    return redirect(url_for('admin.registration_list'))


@admin.route('/registrations/<int:registration_id>/reject', methods=['POST'])
@login_required
@admin_required
def reject_registration(registration_id):
    registration = Registration.query.get_or_404(registration_id)
    registration.status = 'rejected'
    db.session.commit()
    flash(
        f'Registration for {registration.student.name} has been rejected.', 'success')
    return redirect(url_for('admin.registration_list'))

# Settings Management


@admin.route('/settings', methods=['GET', 'POST'])
@login_required
@admin_required
def settings():
    setting = Setting.query.first()
    if not setting:
        setting = Setting(year=datetime.utcnow().year, fee_per_session=50.00)
        db.session.add(setting)
        db.session.commit()

    form = SettingsForm(obj=setting)
    if form.validate_on_submit():
        setting.fee_per_session = form.fee_per_session.data
        db.session.commit()
        flash('Settings updated successfully.', 'success')
        return redirect(url_for('admin.settings'))

    # Get counts for dashboard
    students_count = Student.query.count()
    classes_count = Class.query.count()
    registrations_count = Registration.query.count()
    pending_registrations_count = Registration.query.filter_by(
        status='pending').count()

    return render_template('admin/settings.html',
                           title='System Settings',
                           form=form,
                           setting=setting,
                           students_count=students_count,
                           classes_count=classes_count,
                           registrations_count=registrations_count,
                           pending_registrations_count=pending_registrations_count,
                           now=datetime.now())
